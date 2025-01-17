local table_insert = table.insert
local table_remove = table.remove

function DOTManager:update(t, dt)
	for index = #self._doted_enemies, 1, -1 do
		local dot_info = self._doted_enemies[index]

		if t > dot_info.dot_damage_received_time + self._dot_grace_period and dot_info.dot_counter >= 0.5 then
			self:_damage_dot(dot_info)

			dot_info.dot_counter = 0
		end

		local enemy_alive = alive(dot_info.enemy_unit) and dot_info.enemy_unit:character_damage() and not dot_info.enemy_unit:character_damage():dead()

		if t > dot_info.dot_damage_received_time + dot_info.dot_length or not enemy_alive then
			table.remove(self._doted_enemies, index)
		else
			dot_info.dot_counter = dot_info.dot_counter + dt
		end
	end
end

function DOTManager:check_achievemnts(unit, t)
	if not unit and not alive(unit) then
		return
	end

	if not unit:base() or not unit:base()._tweak_table then
		return
	end

	if CopDamage.is_civilian(unit:base()._tweak_table) then
		return
	end

	local dotted_enemies_by_variant = {}

	for _, data in ipairs(self._doted_enemies) do
		dotted_enemies_by_variant[data.variant] = dotted_enemies_by_variant[data.variant] or {}

		table.insert(dotted_enemies_by_variant[data.variant], data)
	end

	local variant_count_pass, all_pass = nil

	for achievement, achievement_data in pairs(tweak_data.achievement.dot_achievements) do
		variant_count_pass = not achievement_data.count or achievement_data.variant and dotted_enemies_by_variant[achievement_data.variant] and achievement_data.count <= #dotted_enemies_by_variant[achievement_data.variant]
		all_pass = variant_count_pass

		if all_pass and not managers.achievment:award_data(achievement_data) then
			Application:debug("[DOTManager] dot_achievements:", achievement)
		end
	end
end

function DOTManager:add_doted_enemy(enemy_unit, dot_damage_received_time, weapon_unit, dot_length, dot_damage, hurt_animation, variant, weapon_id, apply_hurt_once)
	local dot_info = self:_add_doted_enemy(enemy_unit, dot_damage_received_time, weapon_unit, dot_length, dot_damage, hurt_animation, variant, weapon_id, apply_hurt_once, managers.player:player_unit()) --add proper user_unit in raycastweaponbase

	--[[ 
	--Not in original func, disabling for now
	local weapon = weapon_unit

	if variant == "poison" then
		variant = 1
	elseif variant == "bleed" then
		variant = 2
	elseif variant == "dot" then
		variant = 3
	else
		variant = nil
	end

	if weapon_id ~= nil then
		weapon = managers.player:player_unit()
	end

	managers.network:session():send_to_peers_synched("sync_add_doted_enemy", enemy_unit, variant, weapon, dot_length, dot_damage, managers.player:player_unit(), hurt_animation)
	--]]
end


--function DOTManager:sync_add_dot_damage(enemy_unit, variant, weapon_unit, dot_length, dot_damage, user_unit, hurt_animation, variant, weapon_id)
function DOTManager:sync_add_dot_damage(enemy_unit, dot_damage_received_time, weapon_unit, dot_length, dot_damage)
	if enemy_unit then
		local t = TimerManager:game():time()

		--self:_add_doted_enemy(enemy_unit, t, weapon_unit, dot_length, dot_damage, hurt_animation, variant, weapon_id, user_unit)
		self:_add_doted_enemy(enemy_unit, t, weapon_unit, dot_length, dot_damage)
	end
end

function DOTManager:_add_doted_enemy(enemy_unit, dot_damage_received_time, weapon_unit, dot_length, dot_damage, hurt_animation, variant, weapon_id, apply_hurt_once, user_unit)
	local contains = false

	for _, dot_info in ipairs(self._doted_enemies) do
		if dot_info.enemy_unit == enemy_unit then
			local old_length = dot_info.dot_damage_received_time + dot_info.dot_length
			local new_length = dot_damage_received_time + dot_length

			if old_length < new_length then
				dot_info.dot_length = dot_info.dot_length + new_length - old_length
				dot_info.dot_damage = dot_damage
			end

			dot_info.weapon_unit = weapon_unit
			dot_info.variant = variant
			dot_info.weapon_id = weapon_id
			dot_info.user_unit = user_unit
			dot_info.hurt_animation = dot_info.hurt_animation or hurt_animation
			contains = true

			break
		end
	end

	if not contains then
		local dot_info = {
			dot_counter = 0,
			enemy_unit = enemy_unit,
			dot_damage_received_time = dot_damage_received_time,
			weapon_unit = weapon_unit,
			dot_length = dot_length,
			dot_damage = dot_damage,
			hurt_animation = hurt_animation,
			apply_hurt_once = apply_hurt_once,
			variant = variant,
			weapon_id = weapon_id
		}

		table.insert(self._doted_enemies, dot_info)
		self:check_achievemnts(enemy_unit, dot_damage_received_time)
	end
end

function DOTManager:_damage_dot(dot_info)
	local attacker_unit = managers.player:player_unit()
	local col_ray = {
		unit = dot_info.enemy_unit
	}
	local damage = dot_info.dot_damage
	local ignite_character = false
	local weapon_unit = dot_info.weapon_unit
	local weapon_id = dot_info.weapon_id

	if dot_info.variant then
		if dot_info.variant == "poison" then
			local result = PoisonBulletBase:give_damage_dot(col_ray, weapon_unit, attacker_unit, damage, dot_info.hurt_animation, weapon_id)
	
			if result and alive(weapon_unit) and weapon_unit:base() and weapon_unit:base().thrower_unit then
				local is_dead = result.type == "death"
				weapon_unit:base():_check_achievements(dot_info.enemy_unit, is_dead, result.damage_percent or 0, 1, is_dead and 1 or 0, dot_info.variant)
			end
	
			if dot_info.hurt_animation and dot_info.apply_hurt_once then
				dot_info.hurt_animation = false
			end
		elseif dot_info.variant == "bleed" then
			BleedBulletBase:give_damage_dot(col_ray, weapon_unit, attacker_unit, damage, dot_info.hurt_animation, weapon_id)
		end
	end
end

--Allows for custom dot_damage to be defined.
function DOTManager:create_dot_data(type, custom_data)
	local dot_data = deep_clone(tweak_data:get_dot_type_data(type))

	if custom_data then
		dot_data.dot_length = custom_data.dot_length or dot_data.dot_length
		dot_data.hurt_animation_chance = custom_data.hurt_animation_chance or dot_data.hurt_animation_chance
		dot_data.dot_damage = custom_data.dot_damage or dot_data.dot_damage
	end

	return dot_data
end