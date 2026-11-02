class_name PlayerRig
extends Node3D
## Rig esquelética modular (Skeleton3D + BoneAttachment3D + PhysicalBoneSimulator3D).
## Anima os ossos com física de mola/inércia durante o movimento e ativa ragdoll físico
## real nos ossos presentes quando o jogador é derrubado ou morre.

const BONE_TORSO := "Torso"
const BONE_HEAD := "Head"
const BONE_LEFT_ARM := "LeftArm"
const BONE_RIGHT_ARM := "RightArm"
const BONE_LEFT_LEG := "LeftLeg"
const BONE_RIGHT_LEG := "RightLeg"

const SLOT_TO_BONE: Dictionary = {
	BodyPartDef.Slot.TORSO: BONE_TORSO,
	BodyPartDef.Slot.HEAD: BONE_HEAD,
	BodyPartDef.Slot.LEFT_ARM: BONE_LEFT_ARM,
	BodyPartDef.Slot.RIGHT_ARM: BONE_RIGHT_ARM,
	BodyPartDef.Slot.LEFT_LEG: BONE_LEFT_LEG,
	BodyPartDef.Slot.RIGHT_LEG: BONE_RIGHT_LEG,
}

const BONE_REST_ORIGINS: Dictionary = {
	BONE_TORSO: Vector3(0.0, 0.72, 0.0),
	BONE_HEAD: Vector3(0.0, 0.65, 0.0),
	BONE_LEFT_ARM: Vector3(-0.35, 0.58, 0.0),
	BONE_RIGHT_ARM: Vector3(0.35, 0.58, 0.0),
	BONE_LEFT_LEG: Vector3(-0.14, 0.0, 0.0),
	BONE_RIGHT_LEG: Vector3(0.14, 0.0, 0.0),
}

var skeleton: Skeleton3D
var simulator: PhysicalBoneSimulator3D
var attachments: Dictionary = {}
var physical_bones: Dictionary = {}
var bone_indices: Dictionary = {}

var is_ragdoll := false

var _walk_phase := 0.0
var _breath_phase := 0.0
var _prev_world_pos := Vector3.ZERO
var _prev_velocity := Vector3.ZERO
var _prev_yaw := 0.0
var _initialized_motion := false

## Estado das molas angulares por osso (Vector3 de ângulos de Euler e velocidades angulares).
var _spring_angles: Dictionary = {}
var _spring_vels: Dictionary = {}


func setup_rig(slot_meshes: Dictionary, owner_rid: RID) -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)

	_add_bone(BONE_TORSO, -1, BONE_REST_ORIGINS[BONE_TORSO])
	_add_bone(BONE_HEAD, bone_indices[BONE_TORSO], BONE_REST_ORIGINS[BONE_HEAD])
	_add_bone(BONE_LEFT_ARM, bone_indices[BONE_TORSO], BONE_REST_ORIGINS[BONE_LEFT_ARM])
	_add_bone(BONE_RIGHT_ARM, bone_indices[BONE_TORSO], BONE_REST_ORIGINS[BONE_RIGHT_ARM])
	_add_bone(BONE_LEFT_LEG, bone_indices[BONE_TORSO], BONE_REST_ORIGINS[BONE_LEFT_LEG])
	_add_bone(BONE_RIGHT_LEG, bone_indices[BONE_TORSO], BONE_REST_ORIGINS[BONE_RIGHT_LEG])
	skeleton.reset_bone_poses()

	for slot: BodyPartDef.Slot in BodyPartDef.ALL_SLOTS:
		var bone_name: String = SLOT_TO_BONE[slot]
		var attach := BoneAttachment3D.new()
		attach.name = bone_name + "Attachment"
		attach.bone_name = bone_name
		attach.bone_idx = bone_indices[bone_name]
		skeleton.add_child(attach)
		attachments[slot] = attach

		var mesh_node := slot_meshes.get(slot) as MeshInstance3D
		if mesh_node:
			var local_xform := mesh_node.transform
			mesh_node.get_parent().remove_child(mesh_node)
			attach.add_child(mesh_node)
			mesh_node.transform = local_xform

	_build_physical_bones(owner_rid)


func _add_bone(bone_name: String, parent_idx: int, rest_origin: Vector3) -> void:
	var idx := skeleton.add_bone(bone_name)
	bone_indices[bone_name] = idx
	if parent_idx >= 0:
		skeleton.set_bone_parent(idx, parent_idx)
	var rest := Transform3D(Basis.IDENTITY, rest_origin)
	skeleton.set_bone_rest(idx, rest)
	skeleton.set_bone_pose_position(idx, rest_origin)
	skeleton.set_bone_pose_rotation(idx, Quaternion.IDENTITY)
	_spring_angles[bone_name] = Vector3.ZERO
	_spring_vels[bone_name] = Vector3.ZERO


func _build_physical_bones(owner_rid: RID) -> void:
	simulator = PhysicalBoneSimulator3D.new()
	simulator.name = "PhysicalBoneSimulator3D"
	skeleton.add_child(simulator)

	_create_phys_bone(
		BodyPartDef.Slot.TORSO, BONE_TORSO,
		Vector3(0.44, 0.6, 0.26), Vector3(0.0, 0.305, 0.0),
		14.0, PhysicalBone3D.JOINT_TYPE_NONE, owner_rid
	)
	_create_phys_bone(
		BodyPartDef.Slot.HEAD, BONE_HEAD,
		Vector3(0.3, 0.3, 0.3), Vector3(0.0, 0.17, 0.0),
		3.5, PhysicalBone3D.JOINT_TYPE_CONE, owner_rid
	)
	_create_phys_bone(
		BodyPartDef.Slot.LEFT_ARM, BONE_LEFT_ARM,
		Vector3(0.16, 0.54, 0.16), Vector3(0.0, -0.28, 0.0),
		2.5, PhysicalBone3D.JOINT_TYPE_CONE, owner_rid
	)
	_create_phys_bone(
		BodyPartDef.Slot.RIGHT_ARM, BONE_RIGHT_ARM,
		Vector3(0.16, 0.54, 0.16), Vector3(0.0, -0.28, 0.0),
		2.5, PhysicalBone3D.JOINT_TYPE_CONE, owner_rid
	)
	_create_phys_bone(
		BodyPartDef.Slot.LEFT_LEG, BONE_LEFT_LEG,
		Vector3(0.18, 0.64, 0.18), Vector3(0.0, -0.37, 0.0),
		4.5, PhysicalBone3D.JOINT_TYPE_CONE, owner_rid
	)
	_create_phys_bone(
		BodyPartDef.Slot.RIGHT_LEG, BONE_RIGHT_LEG,
		Vector3(0.18, 0.64, 0.18), Vector3(0.0, -0.37, 0.0),
		4.5, PhysicalBone3D.JOINT_TYPE_CONE, owner_rid
	)

	var all_rids: Array[RID] = [owner_rid]
	for pb: PhysicalBone3D in physical_bones.values():
		all_rids.append(pb.get_rid())
	for pb: PhysicalBone3D in physical_bones.values():
		for rid: RID in all_rids:
			if rid != pb.get_rid():
				PhysicsServer3D.body_add_collision_exception(pb.get_rid(), rid)


func _create_phys_bone(
	slot: BodyPartDef.Slot,
	bone_name: String,
	box_size: Vector3,
	body_offset: Vector3,
	p_mass: float,
	joint_type: PhysicalBone3D.JointType,
	owner_rid: RID
) -> void:
	var pb := PhysicalBone3D.new()
	pb.name = "PhysicalBone_" + bone_name
	pb.bone_name = bone_name
	pb.mass = p_mass
	pb.friction = 0.8
	pb.bounce = 0.15
	pb.linear_damp = 1.2
	pb.angular_damp = 2.5
	pb.collision_layer = 0
	pb.collision_mask = 5
	pb.body_offset = Transform3D(Basis.IDENTITY, body_offset)
	pb.joint_type = joint_type
	if joint_type == PhysicalBone3D.JOINT_TYPE_CONE:
		pb.set("joint_constraints/swing_span", 55.0)
		pb.set("joint_constraints/twist_span", 35.0)

	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape_node.shape = box
	pb.add_child(shape_node)
	simulator.add_child(pb)
	PhysicsServer3D.body_add_collision_exception(pb.get_rid(), owner_rid)
	physical_bones[slot] = pb


func start_ragdoll(player: CharacterBody3D, impulse: Vector3 = Vector3.ZERO) -> void:
	if skeleton == null or simulator == null:
		return
	var active_bones: Array[StringName] = []
	for slot: BodyPartDef.Slot in BodyPartDef.ALL_SLOTS:
		var pb := physical_bones.get(slot) as PhysicalBone3D
		if pb == null:
			continue
		var has_part: bool = player.call("has_body_part", slot)
		pb.collision_mask = 5 if has_part else 0
		if has_part:
			active_bones.append(StringName(SLOT_TO_BONE[slot]))
	if active_bones.is_empty():
		return
	if not is_ragdoll:
		is_ragdoll = true
		simulator.active = true
		simulator.physical_bones_start_simulation(active_bones)
	var torso_pb := physical_bones.get(BodyPartDef.Slot.TORSO) as PhysicalBone3D
	if torso_pb:
		var push := impulse if impulse.length_squared() > 0.01 else (-player.global_transform.basis.z * 3.5 + Vector3.UP * 1.5)
		torso_pb.linear_velocity = push
		torso_pb.angular_velocity = Vector3(randf_range(-4.0, 4.0), randf_range(-2.0, 2.0), randf_range(-4.0, 4.0))
	for slot: BodyPartDef.Slot in [BodyPartDef.Slot.LEFT_ARM, BodyPartDef.Slot.RIGHT_ARM, BodyPartDef.Slot.LEFT_LEG, BodyPartDef.Slot.RIGHT_LEG]:
		if not bool(player.call("has_body_part", slot)):
			continue
		var limb_pb := physical_bones.get(slot) as PhysicalBone3D
		if limb_pb:
			limb_pb.linear_velocity = impulse * 0.8 + Vector3(randf_range(-1.5, 1.5), randf_range(0.5, 2.0), randf_range(-1.5, 1.5))


func stop_ragdoll() -> void:
	if not is_ragdoll or simulator == null:
		return
	is_ragdoll = false
	simulator.physical_bones_stop_simulation()
	simulator.active = false
	for bone_name: String in _spring_angles.keys():
		_spring_angles[bone_name] = Vector3(0.45, 0.0, 0.0)
		_spring_vels[bone_name] = Vector3.ZERO


func refresh_active_parts(player: CharacterBody3D) -> void:
	for slot: BodyPartDef.Slot in BodyPartDef.ALL_SLOTS:
		var pb := physical_bones.get(slot) as PhysicalBone3D
		if pb:
			pb.collision_mask = (5 if is_ragdoll else 0) if bool(player.call("has_body_part", slot)) else 0


func update_pose(
	delta: float,
	player: CharacterBody3D,
	crouching: bool,
	sprinting: bool,
	holding: bool,
	aim_pitch: float,
	voice_level: float
) -> void:
	if skeleton == null:
		return
	if is_ragdoll:
		return

	var world_pos := player.global_position
	var yaw := player.rotation.y
	if not _initialized_motion:
		_prev_world_pos = world_pos
		_prev_yaw = yaw
		_initialized_motion = true

	var dt := maxf(delta, 0.001)
	var world_vel := (world_pos - _prev_world_pos) / dt
	if player.is_multiplayer_authority():
		world_vel = player.velocity
	var world_accel := (world_vel - _prev_velocity) / dt
	var yaw_speed := clampf(wrapf(yaw - _prev_yaw, -PI, PI) / dt, -14.0, 14.0)

	_prev_world_pos = world_pos
	_prev_velocity = world_vel
	_prev_yaw = yaw

	var local_vel := player.global_transform.basis.inverse() * world_vel
	var local_accel := (player.global_transform.basis.inverse() * world_accel).limit_length(35.0)
	var horiz_speed := Vector2(local_vel.x, local_vel.z).length()
	var max_sprint: float = float(player.get("sprint_speed"))
	var move_ratio := clampf(horiz_speed / maxf(max_sprint, 0.1), 0.0, 1.35)
	var leg_count: int = int(player.call("get_leg_count"))

	_breath_phase = wrapf(_breath_phase + delta * (3.8 if sprinting else 1.8), 0.0, TAU)
	if horiz_speed > 0.15:
		var freq := 13.5 if sprinting else (9.2 if not crouching else 6.5)
		if leg_count == 1:
			freq *= 1.25
		_walk_phase = wrapf(_walk_phase + delta * freq * clampf(horiz_speed / 3.5, 0.45, 1.6), 0.0, TAU)
	else:
		_walk_phase = move_toward(_walk_phase, 0.0, delta * 6.0)

	var stride := sin(_walk_phase) * clampf(horiz_speed / 4.2, 0.0, 1.15)
	var opp_stride := sin(_walk_phase + PI) * clampf(horiz_speed / 4.2, 0.0, 1.15)
	var bounce := absf(sin(_walk_phase)) * 0.045 * move_ratio

	# 1. Posição e inclinação do Torso (Pelvis)
	var torso_idx: int = bone_indices[BONE_TORSO]
	var crouch_drop := -0.22 if crouching and leg_count > 0 else 0.0
	var base_torso_pos: Vector3 = BONE_REST_ORIGINS[BONE_TORSO] + Vector3(0.0, crouch_drop + bounce, 0.0)
	skeleton.set_bone_pose_position(torso_idx, base_torso_pos)

	var forward_lean := -0.22 if sprinting else (-0.28 if crouching else -0.05 * move_ratio)
	var strafe_lean := clampf(-local_vel.x * 0.035, -0.18, 0.18)
	var twist_yaw := sin(_walk_phase) * 0.12 * move_ratio
	var torso_target := Vector3(
		forward_lean + sin(_breath_phase) * 0.025,
		twist_yaw,
		strafe_lean
	)
	var torso_inertia := Vector3(
		clampf(local_accel.z * 0.012, -0.25, 0.25),
		clampf(-yaw_speed * 0.02, -0.2, 0.2),
		clampf(-local_accel.x * 0.012, -0.25, 0.25)
	)
	var torso_euler := _step_spring(BONE_TORSO, torso_target, torso_inertia, 110.0, 14.0, delta)
	skeleton.set_bone_pose_rotation(torso_idx, Quaternion.from_euler(torso_euler))

	# 2. Cabeça (acompanha pitch da mira + fala + chicote de inércia)
	var head_idx: int = bone_indices[BONE_HEAD]
	var talk_nod := sin(Time.get_ticks_msec() * 0.035) * clampf(voice_level * 4.5, 0.0, 0.22)
	var head_target := Vector3(
		clampf(aim_pitch * 0.75 - torso_euler.x * 0.6 + talk_nod, -1.1, 1.1),
		clampf(-twist_yaw * 0.6, -0.35, 0.35),
		clampf(-strafe_lean * 0.5, -0.25, 0.25)
	)
	var head_inertia := Vector3(
		clampf(local_accel.z * 0.018 - local_vel.y * 0.03, -0.35, 0.35),
		clampf(-yaw_speed * 0.03, -0.3, 0.3),
		clampf(-local_accel.x * 0.018, -0.3, 0.3)
	)
	var head_euler := _step_spring(BONE_HEAD, head_target, head_inertia, 95.0, 11.0, delta)
	skeleton.set_bone_pose_rotation(head_idx, Quaternion.from_euler(head_euler))

	# 3. Braços (balançam soltos com física de mola ou levantam para segurar Prop)
	var air_flail := clampf(-local_vel.y * 0.08, -0.45, 0.65)
	var left_arm_target: Vector3
	var right_arm_target: Vector3
	if holding:
		var hold_pitch := clampf(1.15 + aim_pitch * 0.75, 0.35, 2.1)
		left_arm_target = Vector3(hold_pitch, 0.18, 0.08)
		right_arm_target = Vector3(hold_pitch, -0.18, -0.08)
	else:
		var arm_amp := 0.85 if sprinting else 0.55
		left_arm_target = Vector3(
			opp_stride * arm_amp + air_flail * 0.4,
			0.0,
			-0.08 - absf(air_flail) * 0.35 - sin(_breath_phase) * 0.03
		)
		right_arm_target = Vector3(
			stride * arm_amp + air_flail * 0.4,
			0.0,
			0.08 + absf(air_flail) * 0.35 + sin(_breath_phase) * 0.03
		)

	var arm_inertia_l := Vector3(
		clampf(local_accel.z * 0.035, -0.6, 0.6),
		clampf(-yaw_speed * 0.045, -0.45, 0.45),
		clampf(-local_accel.x * 0.03 - maxf(yaw_speed, 0.0) * 0.04, -0.55, 0.25)
	)
	var arm_inertia_r := Vector3(
		clampf(local_accel.z * 0.035, -0.6, 0.6),
		clampf(-yaw_speed * 0.045, -0.45, 0.45),
		clampf(-local_accel.x * 0.03 - minf(yaw_speed, 0.0) * 0.04, -0.25, 0.55)
	)
	var l_arm_euler := _step_spring(BONE_LEFT_ARM, left_arm_target, arm_inertia_l, 75.0, 7.5, delta)
	var r_arm_euler := _step_spring(BONE_RIGHT_ARM, right_arm_target, arm_inertia_r, 75.0, 7.5, delta)
	skeleton.set_bone_pose_rotation(bone_indices[BONE_LEFT_ARM], Quaternion.from_euler(l_arm_euler))
	skeleton.set_bone_pose_rotation(bone_indices[BONE_RIGHT_ARM], Quaternion.from_euler(r_arm_euler))

	# 4. Pernas (passada em oposição, pulo/queda e postura agachada)
	var leg_amp := 0.95 if sprinting else 0.68
	var crouch_leg_pitch := 0.38 if crouching else 0.0
	var air_leg_pitch := clampf(local_vel.y * 0.06, -0.45, 0.45)
	var left_leg_target := Vector3(
		stride * leg_amp + crouch_leg_pitch + air_leg_pitch,
		0.0,
		clampf(-local_vel.x * 0.04, -0.22, 0.22)
	)
	var right_leg_target := Vector3(
		opp_stride * leg_amp + crouch_leg_pitch - air_leg_pitch * 0.5,
		0.0,
		clampf(-local_vel.x * 0.04, -0.22, 0.22)
	)
	var leg_inertia := Vector3(
		clampf(local_accel.z * 0.025, -0.45, 0.45),
		0.0,
		clampf(-local_accel.x * 0.025, -0.35, 0.35)
	)
	var l_leg_euler := _step_spring(BONE_LEFT_LEG, left_leg_target, leg_inertia, 110.0, 10.5, delta)
	var r_leg_euler := _step_spring(BONE_RIGHT_LEG, right_leg_target, leg_inertia, 110.0, 10.5, delta)
	skeleton.set_bone_pose_rotation(bone_indices[BONE_LEFT_LEG], Quaternion.from_euler(l_leg_euler))
	skeleton.set_bone_pose_rotation(bone_indices[BONE_RIGHT_LEG], Quaternion.from_euler(r_leg_euler))


func _step_spring(
	bone_name: String,
	target: Vector3,
	impulse_offset: Vector3,
	stiffness: float,
	damping: float,
	delta: float
) -> Vector3:
	var current: Vector3 = _spring_angles[bone_name]
	var vel: Vector3 = _spring_vels[bone_name]
	var desired := target + impulse_offset
	var force := (desired - current) * stiffness - vel * damping
	vel += force * delta
	current += vel * delta
	_spring_angles[bone_name] = current
	_spring_vels[bone_name] = vel
	return current
