# Achieving "Force Pull" + Pinch-Twist Gestures in iOS ARKit / RealityKit

## Goal
Implement a Jedi-like "using the Force" gesture to pull a virtual planet closer (translate toward user) without walking, followed by a pinch-twist to rotate it. For a solar system AR app.

This is **achievable on iOS** with custom code, though more manual than visionOS.

## Required Frameworks & Kits
- **ARKit**: For world tracking, plane detection, and **HandTrackingProvider** (joint positions).
- **RealityKit**: For 3D entities, physics, collisions, gestures, and rendering. Preferred over SceneKit for modern apps.
- **SwiftUI** (optional but recommended): For integrating RealityView and gestures.
- **Vision** (if needed): For additional pose detection.

Key classes:
- `ARKitSession` + `HandTrackingProvider`
- `Entity`, `PhysicsBodyComponent`, `CollisionComponent`
- Hand anchors/joints (wrist, palm, index tip, thumb tip)

## Close Examples & Resources

### 1. Custom Hand Gestures for Manipulation
- **GitHub: CustomGestureDemo** (hakmirzaev) — Demonstrates pinch, drag, flick/throw using raw hand data. Includes pull-like translation and rotation via wrist orientation. Full Swift + RealityKit example. Great base for "Force pull".
  - Detects pinch (thumb-index distance) + movement to apply forces/translation.
  - Adaptable for attracting objects closer.

- **Manipulate AR Objects with Hand Gestures** (blog + GitHub by Shuochen Wang) — Uses hand tracking for translation (drag/pull) and rotation. Includes pan and rotation gestures triggered by hand poses.
  - Code handles thumb-index closed for activation.

- **RealityKit Hand-Controlled Examples** (WWDC 2024 "Discover RealityKit APIs") — Spaceship demo: Pinch distance controls speed (pull-like force), hand tilt for rotation. Physics forces applied based on hand input. Includes planets/asteroids.

### 2. Gesture & Interaction Samples
- Apple's "Transforming RealityKit Entities Using Gestures" sample — SwiftUI gestures (drag, rotate) on entities. Combine with hand tracking for custom triggers.
- RealityKit EntityGestures (`installGestures`) — Built-in drag (move closer), rotation. Extend with hand data for pinch-twist.
- Drag-to-rotate tutorials (e.g., StepInto.Vision labs) — Use `DragGesture` targeted to entities, adapted for hand velocity/orientation.

### 3. Solar System Specific
- Various iOS AR Solar System tutorials (YouTube: CodeWithMac, others) — Place orbiting planets with RealityKit. Add gestures for spinning/inspecting.
- Extend these with hand tracking from above examples.

### 4. Hand Tracking Basics
- Apple's "Tracking and Visualizing Hand Movement" sample — Core code for processing `HandAnchor` updates and joint transforms (e.g., fingertip positions).
- WWDC sessions on ARKit hand tracking — Real-time joint data for custom gestures.

## Implementation Tips from Community & Docs
- **Force Pull (Translate Closer)**:
  - Track palm/index position.
  - On "pull" pose (e.g., open hand → closing while moving toward body): Raycast or calculate vector from planet to user/hand → lerp position or apply physics impulse.
  - Use `entity.position` or `PhysicsMotionComponent` for smooth movement.
  - Visuals: Add temporary "Force" beam (line entity) or particles.

- **Pinch-Twist Rotate**:
  - Detect pinch: Monitor `distance(thumbTip, indexTip)`.
  - While pinched + targeted planet: Apply rotation quaternion from hand/wrist delta to entity's transform.
  - Or use `angularVelocity` on physics body.

- **Targeting**: Ray from fingertip to select planet. Use `CollisionComponent` + input targets.

- **Challenges Mentioned**:
  - iOS hand tracking less precise than visionOS at distance.
  - Needs good lighting; test on LiDAR devices.
  - Custom gesture state machines (pinch evidence counters) for reliability.
  - Combine with system gestures as fallback.

- **Physics for Natural Feel**: Enable `PhysicsBodyComponent` on planets for momentum after pull/rotate.

## Next Steps
1. Start with Apple's hand tracking sample + a basic solar system entity setup.
2. Clone custom gesture GitHub repos.
3. Implement state machine: Idle → Pull (translate) → Pinch-Twist (rotate) → Release.
4. Test iteratively on device.

## Links (as of 2026)
- Search GitHub: "ARKit hand gesture RealityKit iOS"
- WWDC videos: RealityKit APIs, ARKit hand tracking sessions.
- Apple Docs: HandTrackingProvider, Entity gestures.

This gets you very close — full Jedi immersion is doable with these building blocks! Adapt and combine for your app.