import SwiftUI
// SolosAirGoSDK stubs are defined in Config/Types.swift
// #if !targetEnvironment(simulator)
// import SolosAirGoSDK
// #endif

struct KitchenView: View {
    @Bindable var model: AppViewModel
    @State private var savedDishes: [SavedDishSession] = []
    @State private var showNewDishCapture = false
    @State private var showLanguagePicker = false
    @State private var langManager = LanguageManager.shared

    private var passiveVoiceActive: Bool {
        model.glasses.isConnected && !model.showCoachChat && !showNewDishCapture
    }

    private var isFullyConnected: Bool {
        model.glasses.isConnected && model.isGlassesWifiConnected
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if savedDishes.isEmpty {
                    emptyState
                } else {
                    dishList
                }

                newDishButton
            }
            .padding(20)
        }
        .navigationTitle("Your Kitchen")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        showLanguagePicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(langManager.current.flag)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                    }
                    .accessibilityLabel("Change language — \(langManager.current.displayName)")

                    connectionIndicator
                }
            }
        }
        .sheet(isPresented: $showLanguagePicker) {
            LanguagePickerView()
        }
        .navigationDestination(isPresented: $model.showCoachChat) {
            CoachChatView(model: model)
        }
        .navigationDestination(isPresented: $model.showRecipeResult) {
            if let session = model.recipeSession {
                RecipeResultView(model: model, session: session)
            }
        }
        .fullScreenCover(isPresented: $showNewDishCapture) {
            NavigationStack {
                NewDishCaptureView(model: model, onDismiss: { showNewDishCapture = false })
            }
        }
        .passiveVoiceCommands(model: model, isActive: passiveVoiceActive)
        .onAppear {
            reloadDishes()
        }
        .onChange(of: model.shouldShowNewDishCapture) { _, requested in
            guard requested else { return }
            model.shouldShowNewDishCapture = false
            showNewDishCapture = true
        }
        .onChange(of: model.showCoachChat) { _, showing in
            if !showing { reloadDishes() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image("SoloChefLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                Text("What's cooking?")
                    .font(.title2.weight(.semibold))
            }
            Text("Pick up where you left off, or start something new.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(.orange.opacity(0.7))
            Text("No dishes yet")
                .font(.headline)
            Text("Snap a meal with your glasses and your chef will guide you through it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
        .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private var dishList: some View {
        LazyVStack(spacing: 0) {
            ForEach(savedDishes) { dish in
                DishCard(
                    dish: dish,
                    thumbnail: KitchenStore.shared.loadThumbnail(for: dish),
                    onTap: { model.resumeSavedDish(dish) },
                    onDelete: { deleteDish(dish) }
                )
                .padding(.bottom, 12)
            }
        }
    }

    private func deleteDish(_ dish: SavedDishSession) {
        KitchenStore.shared.delete(id: dish.id)
        withAnimation { reloadDishes() }
    }

    private var newDishButton: some View {
        Button {
            showNewDishCapture = true
        } label: {
            Label("New dish", systemImage: "plus.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
    }

    @ViewBuilder
    private var connectionIndicator: some View {
        #if targetEnvironment(simulator)
        EmptyView()
        #else
        HStack(spacing: 6) {
            Circle()
                .fill(isFullyConnected ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            if model.glasses.isConnected, let name = model.glasses.deviceName {
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        #endif
    }

    private func reloadDishes() {
        savedDishes = KitchenStore.shared.loadAll()
    }
}

private struct DishCard: View {
    let dish: SavedDishSession
    let thumbnail: UIImage?
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var showDeleteConfirm = false

    private var dateLabel: String {
        dish.updatedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var phaseLabel: String {
        switch dish.recipeSession.phase {
        case .confirming: "Getting started"
        case .questioning: "Chatting"
        case .gatheringIngredients: "Ingredients"
        case .cookingSteps: "Cooking"
        case .recipeReady: "Recipe ready"
        case .idle: "New"
        }
    }

    private var isInProgress: Bool {
        switch dish.recipeSession.phase {
        case .questioning, .gatheringIngredients, .cookingSteps: return true
        default: return false
        }
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete background
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.red)
                .overlay(
                    Image(systemName: "trash")
                        .foregroundStyle(.white)
                        .font(.title3)
                        .padding(.trailing, 20),
                    alignment: .trailing
                )
                .opacity(offset < -20 ? 1 : 0)

            // Card content
            VStack(spacing: 0) {
                Button(action: onTap) {
                    HStack(spacing: 14) {
                        thumbnailView
                        VStack(alignment: .leading, spacing: 4) {
                            Text(dish.dishName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(dateLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(phaseLabel)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                }
                .buttonStyle(.plain)

                // Continue button for in-progress dishes
                if isInProgress {
                    Divider().padding(.horizontal, 14)
                    Button(action: onTap) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.caption)
                            Text("Continue cooking")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.width < 0 {
                            offset = max(value.translation.width, -80)
                        } else if offset < 0 {
                            offset = min(0, offset + value.translation.width)
                        }
                    }
                    .onEnded { value in
                        if offset < -50 {
                            showDeleteConfirm = true
                        }
                        withAnimation(.spring(response: 0.3)) { offset = 0 }
                    }
            )
        }
        .confirmationDialog("Delete \(dish.dishName)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.12))
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "fork.knife")
                        .foregroundStyle(.orange)
                }
        }
    }
}

#Preview {
    NavigationStack {
        KitchenView(model: AppViewModel())
    }
}
