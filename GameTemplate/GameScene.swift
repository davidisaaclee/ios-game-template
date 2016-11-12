import SpriteKit


// MARK: - Inputs

enum TouchState {
	case down(CGPoint)
	case up
}

enum InputEvent {
	case touch(TouchState)
	case time(TimeInterval)
}



// MARK: - States


struct State {
	struct Body {
		enum State {
			case freefall(initialPosition: CGPoint, initialVelocity: CGPoint, startedAt: TimeInterval)
		}

		var state: Body.State

		func position(at time: TimeInterval) -> CGPoint {
			switch state {
			case let .freefall(initialPosition, initialVelocity, startTime):
				let t = CGFloat(time - startTime)
				return CGPoint(x: initialPosition.x + initialVelocity.x * t,
				               y: initialPosition.y + initialVelocity.y * t)
			}
		}
	}

	var lastUpdated: TimeInterval
	var character: Body
}


struct InputState {
	let systemStartTime: TimeInterval
	var elapsedTime: TimeInterval
	var touchState: TouchState
}


struct RenderState {
	typealias NodeKey = String

	struct Node {
		let id: NodeKey
		let parent: NodeKey?
		var position: CGPoint
	}

	var nodes: [NodeKey: Node]
}




// MARK: - Updaters

protocol Updateable  {
	associatedtype Input
	associatedtype Context

	init(context: Context)
	func updated(with input: Input) -> Self
}


extension State: Updateable {
	typealias Input = InputState
	typealias Context = Input

	init(context: Input) {
		character = Body(state: .freefall(initialPosition: .zero,
		                                  initialVelocity: CGPoint(x: 0, y: -10),
		                                  startedAt: context.elapsedTime))
		lastUpdated = context.elapsedTime
	}

	func updated(with input: InputState) -> State {
		var stateʹ = self
		stateʹ.lastUpdated = input.elapsedTime
		return stateʹ
	}
}


extension InputState: Updateable {
	typealias Input = InputEvent
	typealias Context = TimeInterval

	init(context startTime: TimeInterval) {
		systemStartTime = startTime
		elapsedTime = 0
		touchState = .up
	}

	func updated(with input: InputEvent) -> InputState {
		var inputStateʹ = self

		switch input {
		case let .time(timestamp):
			inputStateʹ.elapsedTime = timestamp - inputStateʹ.systemStartTime

		case let .touch(touchState):
			inputStateʹ.touchState = touchState
		}

		return inputStateʹ
	}
}


extension RenderState: Updateable {
	typealias Input = State

	init(context: Void) {
		nodes = ["root": Node(id: "root", parent: nil, position: .zero)]
	}

	func updated(with input: State) -> RenderState {
		var stateʹ = self
		stateʹ.nodes["character"] =
			Node(id: "character",
			     parent: "root",
			     position: input.character.position(at: input.lastUpdated))
		return stateʹ
	}
}


struct Game {
	var input: InputState? = nil
	var state: State? = nil
	var renderState: RenderState? = nil

	mutating func update(at time: TimeInterval) {
		let inputʹ =
			(input ?? InputState(context: time)).updated(with: .time(time))

		let stateʹ =
			(state ?? State(context: inputʹ)).updated(with: inputʹ)

		let renderStateʹ =
			(renderState ?? RenderState(context: ())).updated(with: stateʹ)

		input = inputʹ
		state = stateʹ
		renderState = renderStateʹ
	}

	mutating func updateInput(with event: InputEvent) {
		input = input?.updated(with: event)
	}
}




class GameScene: SKScene {

	var state: State?
	var renderState: RenderState?
	var game = Game()


	// MARK: - Nodes

	var allNodes: [String: SKNode] = [:]

	let cameraNode: SKCameraNode = { (cameraNode: SKCameraNode) -> SKCameraNode in
		cameraNode.setScale(0.2)
		return cameraNode
	}(SKCameraNode())


	// MARK: - Overrides

	override func didMove(to view: SKView) {
		setupWorld()

		let resetButton = UIButton(type: .system)
		resetButton.setTitle("Reset", for: .normal)
		resetButton.sizeToFit()
		resetButton.addTarget(self,
		                      action: #selector(GameScene.reset),
		                      for: .primaryActionTriggered)
		view.addSubview(resetButton)

		resetButton.translatesAutoresizingMaskIntoConstraints = false
		NSLayoutConstraint.activate([NSLayoutConstraint(item: resetButton,
		                                                attribute: .leading,
		                                                relatedBy: .equal,
		                                                toItem: view,
		                                                attribute: .leading,
		                                                multiplier: 1,
		                                                constant: 20),
		                             NSLayoutConstraint(item: resetButton,
		                                                attribute: .bottom,
		                                                relatedBy: .equal,
		                                                toItem: view,
		                                                attribute: .bottom,
		                                                multiplier: 1,
		                                                constant: -20)])
	}

	override func update(_ currentTime: TimeInterval) {
		game.update(at: currentTime)
		render(game.renderState)
	}

	func render(_ state: RenderState?) {
		guard let state = state else {
			return
		}

		let rootNodeData = state.nodes["root"]!
		let rootNode = allNodes["root"] ?? SKNode()
		rootNode.position = rootNodeData.position
		if rootNode.parent != self {
			addChild(rootNode)
		}
		allNodes["root"] = rootNode

		func updateNode<NodeType: SKNode>(forKey key: RenderState.NodeKey,
		                from nodeData: RenderState.Node,
		                makeNode: () -> NodeType,
		                mutate: (NodeType) -> Void) {
			let node = (allNodes[key] as? NodeType) ?? makeNode()
			if let parentID = nodeData.parent, let parent = allNodes[parentID] {
				if node.parent != parent {
					parent.addChild(node)
				}
			}
			mutate(node)
			allNodes[key] = node
		}

		state.nodes["character"].map { (nodeData) in
			updateNode(forKey: nodeData.id,
			           from: nodeData,
			           makeNode: { SKShapeNode(circleOfRadius: 20) },
			           mutate: { $0.position = nodeData.position })
		}
	}


	// MARK: - Input

	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
		super.touchesBegan(touches, with: event)

		let touch = touches.first!
		game.updateInput(with: .touch(.down(touch.location(in: self))))
	}

	override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
		super.touchesMoved(touches, with: event)

		let touch = touches.first!
		game.updateInput(with: .touch(.down(touch.location(in: self))))
	}

	override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
		super.touchesEnded(touches, with: event)

		game.updateInput(with: .touch(.up))
	}


	// MARK: - Setup

	func setupWorld() {
		addChild(cameraNode)

		camera = cameraNode

		physicsWorld.contactDelegate = self
		physicsWorld.gravity = .zero
	}


	// MARK: - Control

	@objc func reset() {
		state = nil
		renderState = nil

		removeAllChildren()
		setupWorld()
	}

}

enum Category: Int {
	case player = 0x1
	case environment = 0x10
	case none = 0

	static func bitmask(for category: Category) -> UInt32 {
		return Category.bitmask(for: [category])
	}

	static func bitmask(for categories: [Category]) -> UInt32 {
		return categories.reduce(0) { $0 + UInt32($1.rawValue) }
	}

	func isMember(of bitmask: UInt32) -> Bool {
		return (bitmask & Category.bitmask(for: [self])) != 0
	}
}

extension GameScene: SKPhysicsContactDelegate {
	func didBegin(_ contact: SKPhysicsContact) {
		func beganContact(_ contact: SKPhysicsContact,
		                  betweenPlayer playerBody: SKPhysicsBody,
		                  and otherBody: SKPhysicsBody) {
			// TODO
		}

		if Category.player.isMember(of: contact.bodyA.categoryBitMask) {
			beganContact(contact, betweenPlayer: contact.bodyA, and: contact.bodyB)
		} else if Category.player.isMember(of: contact.bodyB.categoryBitMask) {
			beganContact(contact, betweenPlayer: contact.bodyB, and: contact.bodyA)
		}
	}

	func didEnd(_ contact: SKPhysicsContact) {
		func endedContact(_ contact: SKPhysicsContact,
		                  betweenPlayer playerBody: SKPhysicsBody,
		                  and otherBody: SKPhysicsBody) {
			// TODO
		}

		if Category.player.isMember(of: contact.bodyA.categoryBitMask) {
			endedContact(contact, betweenPlayer: contact.bodyA, and: contact.bodyB)
		} else if Category.player.isMember(of: contact.bodyB.categoryBitMask) {
			endedContact(contact, betweenPlayer: contact.bodyB, and: contact.bodyA)
		}
	}
}
