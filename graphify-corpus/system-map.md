# Marrow System Map

## Camera and controls

- `scripts/player_camera_controller.gd`

## Combat and enemies

- `scripts/arrow_projectile.gd`
- `scripts/attack_hitbox.gd`
- `scripts/demo_enemy_camp.gd`
- `scripts/enemy.gd`
- `scripts/enemy_rock_projectile.gd`
- `scripts/locomotion/attack_controller.gd`
- `scripts/locomotion/test_attack.gd`
- `scripts/rig/procedural_enemy_animator.gd`

## Inventory, equipment, and bones

- `scripts/bone.gd`
- `scripts/bone_data_catalog.gd`
- `scripts/bone_database.gd`
- `scripts/bone_definition.gd`
- `scripts/bone_rules_service.gd`
- `scripts/bone_trial_gate.gd`
- `scripts/equipment_rules_service.gd`
- `scripts/limb_bone_pickup.gd`
- `scripts/player_equipment_component.gd`
- `scripts/player_inventory_component.gd`
- `scripts/player_inventory_ui.gd`
- `scripts/ui_bone_item.gd`
- `scripts/ui_bone_slot.gd`
- `scripts/ui_inventory_empty_slot.gd`

## Player orchestration

- `scripts/player.gd`

## Rig and animation

- `scripts/rig/modular_skeleton_rig.gd`
- `scripts/rig/procedural_player_animator.gd`
- `scripts/rig/rig_test_player.gd`

## Supporting gameplay

- `scripts/_rt6.gd`
- `scripts/ballistics_service.gd`
- `scripts/combat_targeting_service.gd`
- `scripts/drop_pickup_rules_service.gd`
- `scripts/game_events.gd`
- `scripts/locomotion/body_graph.gd`
- `scripts/locomotion/body_measure.gd`
- `scripts/locomotion/body_part.gd`
- `scripts/locomotion/chain_ik.gd`
- `scripts/locomotion/contact_lock.gd`
- `scripts/locomotion/detachment.gd`
- `scripts/locomotion/gait_controller.gd`
- `scripts/locomotion/gait_oscillator.gd`
- `scripts/locomotion/gait_pattern.gd`
- `scripts/locomotion/geom2d.gd`
- `scripts/locomotion/impact_response.gd`
- `scripts/locomotion/locomotion_combat.gd`
- `scripts/locomotion/locomotion_gallery.gd`
- `scripts/locomotion/locomotion_lab.gd`
- `scripts/locomotion/locomotion_walk.gd`
- `scripts/locomotion/locomotion_zoo.gd`
- `scripts/locomotion/root_pose_solver.gd`
- `scripts/locomotion/stance_generator.gd`
- `scripts/locomotion/test_body_graph.gd`
- `scripts/locomotion/test_body_measure.gd`
- `scripts/locomotion/test_chain_ik.gd`
- `scripts/locomotion/test_contact_lock.gd`
- `scripts/locomotion/test_detachment.gd`
- `scripts/locomotion/test_gait.gd`
- `scripts/locomotion/test_gait_pattern.gd`
- `scripts/locomotion/test_gallery.gd`
- `scripts/locomotion/test_impact.gd`
- `scripts/locomotion/test_root_pose.gd`
- `scripts/locomotion/test_stance_generator.gd`
- `scripts/locomotion/test_terrain.gd`
- `scripts/locomotion/test_turning.gd`
- `scripts/locomotion_demo_launcher.gd`
- `scripts/main_menu.gd`
- `scripts/player_stats_component.gd`
- `scripts/testing_environment.gd`

## UI and guidance

- `scripts/guide_wisp.gd`
- `scripts/tuning_menu_ui.gd`
- `scripts/tutorial_island_builder.gd`

## World, goals, and progression

- `scripts/arena_goal_manager.gd`
- `scripts/exit_portal.gd`
- `scripts/open_world_stage.gd`
- `scripts/world_map_manager.gd`

## Scene Entry Points

- `scenes/attack_hitbox.tscn` composes `scripts/attack_hitbox.gd`.
- `scenes/bone.tscn` composes `scripts/bone.gd`.
- `scenes/bone_trial_gate.tscn` composes `scripts/bone_trial_gate.gd`.
- `scenes/dummy_testing_environment.tscn` composes `scripts/testing_environment.gd`.
- `scenes/enemy.tscn` composes `scripts/enemy.gd`, `scripts/rig/modular_skeleton_rig.gd`, `scripts/rig/procedural_enemy_animator.gd`.
- `scenes/exit_portal.tscn` composes `scripts/exit_portal.gd`.
- `scenes/guide_wisp.tscn` composes `scripts/guide_wisp.gd`.
- `scenes/locomotion_combat.tscn` composes `scripts/locomotion/locomotion_combat.gd`.
- `scenes/locomotion_gallery.tscn` composes `scripts/locomotion/locomotion_gallery.gd`.
- `scenes/locomotion_lab.tscn` composes `scripts/locomotion/locomotion_lab.gd`.
- `scenes/locomotion_walk.tscn` composes `scripts/locomotion/locomotion_walk.gd`.
- `scenes/main.tscn` composes `scripts/arena_goal_manager.gd`, `scripts/world_map_manager.gd`, `scripts/tutorial_island_builder.gd`.
- `scenes/main_menu.tscn` composes `scripts/main_menu.gd`.
- `scenes/open_world_stage.tscn` composes `scripts/open_world_stage.gd`.
- `scenes/player.tscn` composes `scripts/player.gd`, `scripts/rig/modular_skeleton_rig.gd`, `scripts/rig/procedural_player_animator.gd`, `scripts/player_camera_controller.gd`, `scripts/tuning_menu_ui.gd`.
- `scenes/rig_test.tscn` composes `scripts/rig/rig_test_player.gd`, `scripts/rig/modular_skeleton_rig.gd`, `scripts/rig/procedural_player_animator.gd`.
- `scenes/testing_environment.tscn` composes `scripts/testing_environment.gd`.
