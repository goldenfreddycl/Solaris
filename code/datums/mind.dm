/*	Note from Carnie:
		The way datum/mind stuff works has been changed a lot.
		Minds now represent IC characters rather than following a client around constantly.

	Guidelines for using minds properly:

	-	Never mind.transfer_to(ghost). The var/current and var/original of a mind must always be of type mob/living!
		ghost.mind is however used as a reference to the ghost's corpse

	-	When creating a new mob for an existing IC character (e.g. cloning a dead guy or borging a brain of a human)
		the existing mind of the old mob should be transfered to the new mob like so:

			mind.transfer_to(new_mob)

	-	You must not assign key= or ckey= after transfer_to() since the transfer_to transfers the client for you.
		By setting key or ckey explicitly after transferring the mind with transfer_to you will cause bugs like DCing
		the player.

	-	IMPORTANT NOTE 2, if you want a player to become a ghost, use mob.ghostize() It does all the hard work for you.

	-	When creating a new mob which will be a new IC character (e.g. putting a shade in a construct or randomly selecting
		a ghost to become a xeno during an event). Simply assign the key or ckey like you've always done.

			new_mob.key = key

		The Login proc will handle making a new mind for that mobtype (including setting up stuff like mind.name). Simple!
		However if you want that mind to have any special properties like being a traitor etc you will have to do that
		yourself.

*/


/datum/mind
	var/key
	var/name				//replaces mob/var/original_name
	var/ghostname			//replaces name for observers name if set
	var/mob/living/current
	var/active = 0

	var/memory

	var/assigned_role
	var/special_role
	var/list/restricted_roles = list()

	var/list/spell_list = list() // Wizard mode & "Give Spell" badmin button.

	var/spell_points
	var/used_spell_points
	var/vamp_points //used for leveling vampire skills
	var/used_vamp_points
	var/movemovemovetext = "Move!!"
	var/takeaimtext = "Take aim!!"
	var/holdtext = "Hold!!"
	var/onfeettext = "On your feet!!"
	var/focustargettext = "Focus target!!"

	var/linglink
	var/datum/martial_art/martial_art
	var/static/default_martial_art = new/datum/martial_art
	var/miming = 0 // Mime's vow of silence
	var/list/antag_datums
	var/antag_hud_icon_state = null //this mind's ANTAG_HUD should have this icon_state
	var/datum/atom_hud/antag/antag_hud = null //this mind's antag HUD
	var/damnation_type = 0
	var/datum/mind/soulOwner //who owns the soul.  Under normal circumstances, this will point to src
	var/hasSoul = TRUE // If false, renders the character unable to sell their soul.
	var/isholy = FALSE //is this person a chaplain or admin role allowed to use bibles

	var/mob/living/enslaved_to //If this mind's master is another mob (i.e. adamantine golems)
	var/datum/language_holder/language_holder
	var/unconvertable = FALSE
	var/late_joiner = FALSE

	var/last_death = 0

	var/force_escaped = FALSE  // Set by Into The Sunset command of the shuttle manipulator

	var/list/learned_recipes //List of learned recipe TYPES.

	///Assoc list of skills - level
	var/list/known_skills = list()
	///Assoc list of skills - exp
	var/list/skill_experience = list()

	var/list/special_items = list()

	var/list/areas_entered = list()

	var/list/known_people = list() //contains person, their job, and their voice color

	var/list/notes = list() //RTD add notes button

	var/lastrecipe

	var/datum/sleep_adv/sleep_adv = null

	var/mugshot_set = FALSE

	var/heretic_nickname   // Nickname used for heretic commune

	var/list/summons_list = list() //List of summons, used to quickly update their factions in case of a faction change.
	var/list/summons_additional_factions = list() //saves any factions added by the "Mark of the Gravebound" spell so future summons get those added too.

	var/capped_arcane_melee = SKILL_LEVEL_CAPPED_ARCANE_CASTER //Numeral, used to cap arcane using melee weapon on some classes. Well on Warlock.
	var/obj/item/warlock_weapons = list() // Saves the warlock summoned weapon if any.
	var/warlock_weapon_types = list() // Saves the selected weapontype if replacement needed.

/datum/mind/New(key)
	src.key = key
	soulOwner = src
	martial_art = default_martial_art
	sleep_adv = new /datum/sleep_adv(src)

/datum/mind/Destroy()
	SSticker.minds -= src
	QDEL_NULL(sleep_adv)
	if(islist(antag_datums))
		QDEL_LIST(antag_datums)
	return ..()

/proc/get_minds(role)
	. = list()
	for(var/datum/mind/M in SSticker.minds)
		var/is_role = TRUE
		if(role)
			is_role = FALSE
			if(M.special_role == role)
				is_role = TRUE
			else
				if(M.assigned_role == role)
					is_role = TRUE
		if(is_role)
			. += M

/datum/mind/proc/i_know_person(person) //they are added to ours
	if(!person)
		return
	if(person == src || person == src.current)
		return
	if(istype(person, /datum/mind))
		var/datum/mind/M = person
		person = M.current
	if(ishuman(person))
		var/mob/living/carbon/human/H = person
		if(!known_people[H.real_name])
			known_people[H.real_name] = list()
		known_people[H.real_name]["VCOLOR"] = H.voice_color
		var/used_title = H.get_role_title()
		if(!used_title)
			used_title = "unknown"
		known_people[H.real_name]["FJOB"] = used_title
		var/referred_gender
		switch(H.pronouns)
			if(HE_HIM)
				referred_gender = "Male"
			if(SHE_HER)
				referred_gender = "Female"
			else
				referred_gender = "Androgynous"
		known_people[H.real_name]["FGENDER"] = referred_gender
		known_people[H.real_name]["FSPECIES"] = H.dna.species.name
		known_people[H.real_name]["FAGE"] = H.age

/datum/mind/proc/person_knows_me(person) //we are added to their lists
	if(!person)
		return
	if(person == src || person == src.current)
		return
	if(ishuman(person))
		var/mob/living/carbon/human/guy = person
		person = guy.mind
	if(istype(person, /datum/mind))
		var/datum/mind/M = person
		if(M.known_people)
			if(ishuman(current))
				var/mob/living/carbon/human/H = current
				if(!M.known_people[H.real_name])
					M.known_people[H.real_name] = list()
				M.known_people[H.real_name]["VCOLOR"] = H.voice_color
				var/used_title = H.get_role_title()
				if(!used_title)
					used_title = "unknown"
				M.known_people[H.real_name]["FJOB"] = used_title
				var/referred_gender
				switch(H.pronouns)
					if(HE_HIM)
						referred_gender = "Male"
					if(SHE_HER)
						referred_gender = "Female"
					else
						referred_gender = "Androgynous"
				M.known_people[H.real_name]["FGENDER"] = referred_gender
				M.known_people[H.real_name]["FSPECIES"] = H.dna.species.name
				M.known_people[H.real_name]["FAGE"] = H.age
				

/datum/mind/proc/do_i_know(datum/mind/person, name)
	if(!person && !name)
		return
	if(person)
		var/mob/living/carbon/human/H = person.current
		if(!istype(H))
			return
		for(var/P in known_people)
			if(H.real_name == P)
				return TRUE
	if(name)
		for(var/P in known_people)
			if(name == P)
				return TRUE

/datum/mind/proc/become_unknown_to(person) //we are removed from mind
	if(!person)
		return
	if(person == src)
		return
	var/datum/mind/M = person
	var/mob/living/carbon/human/H = current
	if(M.known_people && istype(H))
		M.known_people -= H.real_name


/datum/mind/proc/unknow_all_people()
	known_people = list()


/datum/mind/proc/display_known_people(mob/user)
	if(!user)
		return
	if(!known_people.len)
		return
	known_people = sortList(known_people)
	var/contents = "<center>People that [name] knows:</center><BR>"
	for(var/P in known_people)
		var/fcolor = known_people[P]["VCOLOR"]
		if(!fcolor)
			continue
		var/fjob = known_people[P]["FJOB"]
		var/fgender = known_people[P]["FGENDER"]
		var/fspecies = known_people[P]["FSPECIES"]
		var/fage = known_people[P]["FAGE"]
		var/fheresy = known_people[P]["FHERESY"]
		if(fcolor && fjob)
			if (fheresy)
				contents +="<B><font color=#f1d669>[fheresy]</font></B> "
			contents += "<B><font color=#[fcolor];text-shadow:0 0 10px #8d5958, 0 0 20px #8d5958, 0 0 30px #8d5958, 0 0 40px #8d5958, 0 0 50px #e60073, 0 0 60px #8d5958, 0 0 70px #8d5958;>[P]</font></B><BR>[fjob], [fspecies], [capitalize(fgender)], [fage]"
			contents += "<BR>"

	var/datum/browser/popup = new(user, "PEOPLEIKNOW", "", 260, 400)
	popup.set_content(contents)
	popup.open()


/datum/mind/proc/get_language_holder()
	if(!language_holder)
		var/datum/language_holder/L = current.get_language_holder(shadow=FALSE)
		language_holder = L.copy(src)

	return language_holder

/datum/mind/proc/transfer_to(mob/new_character, force_key_move = 0)
	if(current)	// remove ourself from our old body's mind variable
		current.mind = null
		UnregisterSignal(current, COMSIG_MOB_DEATH)
		SStgui.on_transfer(current, new_character)

	if(!language_holder)
		var/datum/language_holder/mob_holder = new_character.get_language_holder(shadow = FALSE)
		language_holder = mob_holder.copy(src)

	if(key)
		if(new_character.key != key)					//if we're transferring into a body with a key associated which is not ours
			if(new_character.key)
				testing("ghostizz")
				new_character.ghostize(1)						//we'll need to ghostize so that key isn't mobless.
	else
		key = new_character.key

	if(new_character.mind)								//disassociate any mind currently in our new body's mind variable
		new_character.mind.current = null

	var/datum/atom_hud/antag/hud_to_transfer = antag_hud//we need this because leave_hud() will clear this list
	var/mob/living/old_current = current
	if(current)
		current.transfer_observers_to(new_character)	//transfer anyone observing the old character to the new one
	current = new_character								//associate ourself with our new body
	new_character.mind = src							//and associate our new body with ourself
	for(var/datum/antagonist/A in antag_datums)	//Makes sure all antag datums effects are applied in the new body
		A.on_body_transfer(old_current, current)
	if(iscarbon(new_character))
		var/mob/living/carbon/C = new_character
		C.last_mind = src
	transfer_antag_huds(hud_to_transfer)				//inherit the antag HUD
	transfer_actions(new_character)
	transfer_martial_arts(new_character)
	RegisterSignal(new_character, COMSIG_MOB_DEATH, PROC_REF(set_death_time))
	if(active || force_key_move)
		testing("dotransfer to [new_character]")
		new_character.key = key		//now transfer the key to link the client to our new body
	new_character.update_fov_angles()


	///Adjust experience of a specific skill
/datum/mind/proc/adjust_experience(skill, amt, silent = FALSE)
	var/datum/skill/S = GetSkillRef(skill)
	skill_experience[S] = max(0, skill_experience[S] + amt) //Prevent going below 0
	var/old_level = known_skills[S]
	switch(skill_experience[S])
		if(SKILL_EXP_LEGENDARY to INFINITY)
			known_skills[S] = SKILL_LEVEL_LEGENDARY

		if(SKILL_EXP_MASTER to SKILL_EXP_LEGENDARY)
			known_skills[S] = SKILL_LEVEL_MASTER

		if(SKILL_EXP_EXPERT to SKILL_EXP_MASTER)
			known_skills[S] = SKILL_LEVEL_EXPERT

		if(SKILL_EXP_JOURNEYMAN to SKILL_EXP_EXPERT)
			known_skills[S] = SKILL_LEVEL_JOURNEYMAN

		if(SKILL_EXP_APPRENTICE to SKILL_EXP_JOURNEYMAN)
			known_skills[S] = SKILL_LEVEL_APPRENTICE

		if(SKILL_EXP_NOVICE to SKILL_EXP_APPRENTICE)
			known_skills[S] = SKILL_LEVEL_NOVICE

		if(0 to SKILL_EXP_NOVICE)
			known_skills[S] = SKILL_LEVEL_NONE

	if(isnull(old_level) || known_skills[S] == old_level)
		return //same level or we just started earning xp towards the first level.
	if(silent)
		return
	// ratio = round(skill_experience[S]/limit,1) * 100
	// to_chat(current, "<span class='nicegreen'> My [S.name] is around [ratio]% of the way there.")
	//TODO add some bar hud or something, i think i seen a request like that somewhere
	if(known_skills[S] >= old_level)
		if(known_skills[S] > old_level)
			to_chat(current, span_nicegreen("My [S.name] grows to [SSskills.level_names[known_skills[S]]]!"))
			S.skill_level_effect(src, known_skills[S])
			if(skill == /datum/skill/magic/vampirism)
				adjust_vamppoints(2) //adding 2 points per vampire level
			if (skill == /datum/skill/magic/arcane && get_skill_level(skill) == SKILL_LEVEL_LEGENDARY)
				if (!HAS_TRAIT(current, TRAIT_MAGIC_TALENT))
					ADD_TRAIT(current, TRAIT_ARCANE_GATES, TRAIT_GENERIC)
					to_chat(current, span_nicegreen("I have peeked into the arcane gates and obtained an important truth!"))
				if (HAS_TRAIT(current, TRAIT_ARCANE_T3))
					adjust_spellpoints(3)
			if ((skill == /datum/skill/magic/arcane && get_skill_level(skill) == SKILL_LEVEL_MASTER) && HAS_TRAIT(current, TRAIT_MAGIC_TUTOR))
				current.mind.AddSpell(new /obj/effect/proc_holder/spell/invoked/tutor)
				to_chat(current, span_nicegreen("I am confident enough to take students of the Arcane under my wing!"))
	else
		to_chat(current, span_warning("My [S.name] has weakened to [SSskills.level_names[known_skills[S]]]!"))

/datum/mind/proc/adjust_skillrank_up_to(skill, amt, silent = FALSE)
	var/proper_amt = amt - get_skill_level(skill)
	if(proper_amt <= 0)
		return
	adjust_skillrank(skill, proper_amt, silent)

/datum/mind/proc/adjust_skillrank_down_to(skill, amt, silent = FALSE)
	var/proper_amt = get_skill_level(skill) - amt
	if(proper_amt <= 0)
		return
	adjust_skillrank(skill, -proper_amt, silent)

/datum/mind/proc/adjust_skillrank_by_up_to(skill, amount, max_rank, silent = FALSE)
	var/current = get_skill_level(skill)
	var/target = min(current + amount, max_rank)
	adjust_skillrank_up_to(skill, target, silent)

/datum/mind/proc/adjust_skillrank_down_by_up_to(skill, amount, min_rank, silent = FALSE)
	var/current = get_skill_level(skill)
	var/target = max(current - amount, min_rank)
	adjust_skillrank_down_to(skill, target, silent)

/datum/mind/proc/adjust_skillrank(skill, amt, silent = FALSE)
	var/datum/skill/S = GetSkillRef(skill)
	var/amt2gain = 0
	if(skill == /datum/skill/magic/vampirism)
		adjust_vamppoints(amt*2) //adding 2 points per vampire level
	for(var/i in 1 to amt)
		switch(skill_experience[S])
			if(SKILL_EXP_MASTER to SKILL_EXP_LEGENDARY)
				amt2gain = SKILL_EXP_LEGENDARY-skill_experience[S]
			if(SKILL_EXP_EXPERT to SKILL_EXP_MASTER)
				amt2gain = SKILL_EXP_MASTER-skill_experience[S]
			if(SKILL_EXP_JOURNEYMAN to SKILL_EXP_EXPERT)
				amt2gain = SKILL_EXP_EXPERT-skill_experience[S]
			if(SKILL_EXP_APPRENTICE to SKILL_EXP_JOURNEYMAN)
				amt2gain = SKILL_EXP_JOURNEYMAN-skill_experience[S]
			if(SKILL_EXP_NOVICE to SKILL_EXP_APPRENTICE)
				amt2gain = SKILL_EXP_APPRENTICE-skill_experience[S]
			if(0 to SKILL_EXP_NOVICE)
				amt2gain = SKILL_EXP_NOVICE-skill_experience[S] + 1
		if(!skill_experience[S])
			amt2gain = SKILL_EXP_NOVICE+1
		skill_experience[S] = max(0, skill_experience[S] + amt2gain) //Prevent going below 0
	var/old_level = get_skill_level(skill)
	switch(skill_experience[S])
		if(SKILL_EXP_LEGENDARY to INFINITY)
			known_skills[S] = SKILL_LEVEL_LEGENDARY
		if(SKILL_EXP_MASTER to SKILL_EXP_LEGENDARY)
			known_skills[S] = SKILL_LEVEL_MASTER
		if(SKILL_EXP_EXPERT to SKILL_EXP_MASTER)
			known_skills[S] = SKILL_LEVEL_EXPERT
		if(SKILL_EXP_JOURNEYMAN to SKILL_EXP_EXPERT)
			known_skills[S] = SKILL_LEVEL_JOURNEYMAN
		if(SKILL_EXP_APPRENTICE to SKILL_EXP_JOURNEYMAN)
			known_skills[S] = SKILL_LEVEL_APPRENTICE
		if(SKILL_EXP_NOVICE to SKILL_EXP_APPRENTICE)
			known_skills[S] = SKILL_LEVEL_NOVICE
		if(0 to SKILL_EXP_NOVICE)
			known_skills[S] = SKILL_LEVEL_NONE
	if (skill == /datum/skill/magic/arcane && get_skill_level(skill) == SKILL_LEVEL_LEGENDARY)
		if (!HAS_TRAIT(current, TRAIT_MAGIC_TALENT))
			ADD_TRAIT(current, TRAIT_ARCANE_GATES, TRAIT_GENERIC)
			to_chat(current, span_nicegreen("I have peeked into the arcane gates and obtained an important truth!"))
		if (HAS_TRAIT(current, TRAIT_ARCANE_T3))
			adjust_spellpoints(3)
	if ((skill == /datum/skill/magic/arcane && get_skill_level(skill) == SKILL_LEVEL_MASTER) && HAS_TRAIT(current, TRAIT_MAGIC_TUTOR))
		current.mind.AddSpell(new /obj/effect/proc_holder/spell/invoked/tutor)
		to_chat(current, span_nicegreen("I am confident enough to take students of the Arcane under my wing!"))
	if(known_skills[S] == old_level)
		return //same level or we just started earning xp towards the first level.
	if(silent)
		return
	if(known_skills[S] >= old_level)
		to_chat(current, span_nicegreen("I feel like I've become more proficient at [lowertext(S.name)]!"))
	else
		to_chat(current, span_warning("I feel like I've become worse at [lowertext(S.name)]!"))

// adjusts the amount of available spellpoints
/datum/mind/proc/adjust_spellpoints(points)
	spell_points += points
	check_learnspell() //check if we need to add or remove the learning spell

// adjusts the amount of available vamp points
/datum/mind/proc/adjust_vamppoints(points)
	vamp_points += points
	check_learnvampspellperk() //check if we need to add or remove the learning spell, not sure this will work right

///Gets the skill's singleton and returns the result of its get_skill_speed_modifier
/datum/mind/proc/get_skill_speed_modifier(skill)
	var/datum/skill/S = GetSkillRef(skill)
	return S.get_skill_speed_modifier(known_skills[S] || SKILL_LEVEL_NONE)

/datum/mind/proc/get_skill_level(skill)
	var/datum/skill/S = GetSkillRef(skill)
	return known_skills[S] || SKILL_LEVEL_NONE

///Helper proc that lets us manually cap skill level taken into account for weapon checks.
/datum/mind/proc/get_skill_level_capped(skill)
	var/datum/skill/checked_skill = GetSkillRef(skill)
	if(!checked_skill)
		return SKILL_LEVEL_NONE

	var/level = known_skills[checked_skill] || SKILL_LEVEL_NONE

	if(istype(checked_skill, /datum/skill/magic/arcane) && isnum(src.capped_arcane_melee))
		return min(level, capped_arcane_melee)

	return level

/datum/mind/proc/print_levels(user)
	var/list/shown_skills = list()
	for(var/i in known_skills)
		if(known_skills[i]) //Do we actually have a level in this?
			shown_skills += i
	if(!length(shown_skills))
		to_chat(user, span_warning("I don't have any skills."))
		return
	var/msg = ""
	msg += span_info("*---------*\n")
	for(var/datum/skill/i in shown_skills)
		var/can_advance_post = sleep_adv.enough_sleep_xp_to_advance(i.type, 1)
		var/capped_post = sleep_adv.enough_sleep_xp_to_advance(i.type, 2)
		var/rankup_postfix = capped_post ? span_nicegreen(" <b>(!!)</b>") : can_advance_post ? span_nicegreen(" <b>(!)</b>") : ""
		msg += "[i] - [SSskills.level_names[known_skills[i]]][rankup_postfix]"
		msg += span_info(" <a href='?src=[REF(i)];skill_detail=1'>{?}</a>\n")
	msg += "</span>"

	to_chat(user, msg)


/datum/mind/proc/set_death_time()
	last_death = world.time

/datum/mind/proc/store_memory(new_text)
	var/newlength = length(memory) + length(new_text)
	if (newlength > MAX_MESSAGE_LEN * 100)
		memory = copytext(memory, -newlength-MAX_MESSAGE_LEN * 100)
	memory += "[new_text]<BR>"

/datum/mind/proc/wipe_memory()
	memory = null

// Datum antag mind procs
/datum/mind/proc/add_antag_datum(datum_type_or_instance, team, admin_panel)
	if(!datum_type_or_instance)
		return
	var/datum/antagonist/A
	if(!ispath(datum_type_or_instance))
		A = datum_type_or_instance
		if(!istype(A))
			return
	else
		A = new datum_type_or_instance()
	//Choose snowflake variation if antagonist handles it
	var/datum/antagonist/S = A.specialization(src)
	if(S && S != A)
		qdel(A)
		A = S
	if(!A.can_be_owned(src))
		qdel(A)
		return
	A.owner = src
	LAZYADD(antag_datums, A)
	A.create_team(team)
	var/datum/team/antag_team = A.get_team()
	if(antag_team)
		antag_team.add_member(src)
	if(admin_panel) //Admin panelled has special behaviour with zombie
		A.on_gain(TRUE)
	else
		A.on_gain()
	log_game("[key_name(src)] has gained antag datum [A.name]([A.type])")
	return A

/datum/mind/proc/remove_antag_datum(datum_type)
	if(!datum_type)
		return
	var/datum/antagonist/A = has_antag_datum(datum_type)
	if(A)
		A.on_removal()
		return TRUE


/datum/mind/proc/remove_all_antag_datums() //For the Lazy amongst us.
	for(var/a in antag_datums)
		var/datum/antagonist/A = a
		A.on_removal()

/datum/mind/proc/has_antag_datum(datum_type, check_subtypes = TRUE)
	if(!datum_type)
		return
	. = FALSE
	for(var/a in antag_datums)
		var/datum/antagonist/A = a
		if(check_subtypes && istype(A, datum_type))
			return A
		else
			if(istype(A))
				if(A.type == datum_type)
					return A


/datum/mind/proc/remove_traitor()
	remove_antag_datum(/datum/antagonist/traitor)


/datum/mind/proc/remove_all_antag() //For the Lazy amongst us.
	remove_traitor()

/datum/mind/proc/equip_traitor(employer = "The Syndicate", silent = FALSE, datum/antagonist/uplink_owner)
	return


//Link a new mobs mind to the creator of said mob. They will join any team they are currently on, and will only switch teams when their creator does.

/datum/mind/proc/enslave_mind_to_creator(mob/living/creator)
	enslaved_to = creator

	current.faction |= creator.faction
	creator.faction |= current.faction

	if(creator.mind.special_role)
		message_admins("[ADMIN_LOOKUPFLW(current)] has been created by [ADMIN_LOOKUPFLW(creator)], an antagonist.")
		to_chat(current, span_danger("Despite my creators current allegiances, my true master remains [creator.real_name]. If their loyalties change, so do yours. This will never change unless my creator's body is destroyed."))

/datum/mind/proc/show_memory(mob/recipient, window=1)
	if(!recipient)
		recipient = current
	var/output = "<B>[current.real_name]'s Memories:</B><br>"
	output += memory


	var/list/all_objectives = list()
	for(var/datum/antagonist/A in antag_datums)
		output += A.antag_memory
		all_objectives |= A.objectives

	if(all_objectives.len)
		output += "<B>Objectives:</B>"
		var/obj_count = 1
		for(var/datum/objective/objective in all_objectives)
			output += "<br><B>Objective #[obj_count++]</B>: [objective.explanation_text]"
//			var/list/datum/mind/other_owners = objective.get_owners() - src
//			if(other_owners.len)
//				output += "<ul>"
//				for(var/datum/mind/M in other_owners)
//					output += "<li>Conspirator: [M.name]</li>"
//				output += "</ul>"

/datum/mind/Topic(href, href_list)
	if(!check_rights(R_ADMIN))
		return

	var/self_antagging = usr == current

	if(href_list["add_antag"])
		add_antag_wrapper(text2path(href_list["add_antag"]),usr)
	if(href_list["remove_antag"])
		var/datum/antagonist/A = locate(href_list["remove_antag"]) in antag_datums
		if(!istype(A))
			to_chat(usr,span_warning("Invalid antagonist ref to be removed."))
			return
		A.admin_remove(usr)

	if (href_list["role_edit"])
		var/new_role = input("Select new role", "Assigned role", assigned_role) as null|anything in sortList(get_all_jobs())
		if (!new_role)
			return
		assigned_role = new_role

	else if (href_list["memory_edit"])
		var/new_memo = copytext(sanitize(input("Write new memory", "Memory", memory) as null|message),1,MAX_MESSAGE_LEN)
		if (isnull(new_memo))
			return
		memory = new_memo

	else if (href_list["obj_edit"] || href_list["obj_add"])
		var/objective_pos //Edited objectives need to keep same order in antag objective list
		var/def_value
		var/datum/antagonist/target_antag
		var/datum/objective/old_objective //The old objective we're replacing/editing
		var/datum/objective/new_objective //New objective we're be adding

		if(href_list["obj_edit"])
			for(var/datum/antagonist/A in antag_datums)
				old_objective = locate(href_list["obj_edit"]) in A.objectives
				if(old_objective)
					target_antag = A
					objective_pos = A.objectives.Find(old_objective)
					break
			if(!old_objective)
				to_chat(usr,"Invalid objective.")
				return
		else
			if(href_list["target_antag"])
				var/datum/antagonist/X = locate(href_list["target_antag"]) in antag_datums
				if(X)
					target_antag = X
			if(!target_antag)
				switch(antag_datums.len)
					if(0)
						target_antag = add_antag_datum(/datum/antagonist/custom)
					if(1)
						target_antag = antag_datums[1]
					else
						var/datum/antagonist/target = input("Which antagonist gets the objective:", "Antagonist", "(new custom antag)") as null|anything in sortList(antag_datums) + "(new custom antag)"
						if (QDELETED(target))
							return
						else if(target == "(new custom antag)")
							target_antag = add_antag_datum(/datum/antagonist/custom)
						else
							target_antag = target

		if(!GLOB.admin_objective_list)
			generate_admin_objective_list()

		if(old_objective)
			if(old_objective.name in GLOB.admin_objective_list)
				def_value = old_objective.name

		var/selected_type = input("Select objective type:", "Objective type", def_value) as null|anything in GLOB.admin_objective_list
		selected_type = GLOB.admin_objective_list[selected_type]
		if (!selected_type)
			return

		if(!old_objective)
			//Add new one
			new_objective = new selected_type
			new_objective.owner = src
			new_objective.admin_edit(usr)
			target_antag.objectives += new_objective
			message_admins("[key_name_admin(usr)] added a new objective for [current]: [new_objective.explanation_text]")
			log_admin("[key_name(usr)] added a new objective for [current]: [new_objective.explanation_text]")
		else
			if(old_objective.type == selected_type)
				//Edit the old
				old_objective.admin_edit(usr)
				new_objective = old_objective
			else
				//Replace the old
				new_objective = new selected_type
				new_objective.owner = src
				new_objective.admin_edit(usr)
				target_antag.objectives -= old_objective
				target_antag.objectives.Insert(objective_pos, new_objective)
			message_admins("[key_name_admin(usr)] edited [current]'s objective to [new_objective.explanation_text]")
			log_admin("[key_name(usr)] edited [current]'s objective to [new_objective.explanation_text]")

	else if (href_list["obj_delete"])
		var/datum/objective/objective
		for(var/datum/antagonist/A in antag_datums)
			objective = locate(href_list["obj_delete"]) in A.objectives
			if(istype(objective))
				A.objectives -= objective
				break
		if(!objective)
			to_chat(usr,"Invalid objective.")
			return
		//qdel(objective) Needs cleaning objective destroys
		message_admins("[key_name_admin(usr)] removed an objective for [current]: [objective.explanation_text]")
		log_admin("[key_name(usr)] removed an objective for [current]: [objective.explanation_text]")

	else if(href_list["obj_completed"])
		var/datum/objective/objective
		for(var/datum/antagonist/A in antag_datums)
			objective = locate(href_list["obj_completed"]) in A.objectives
			if(istype(objective))
				objective = objective
				break
		if(!objective)
			to_chat(usr,"Invalid objective.")
			return
		objective.completed = !objective.completed
		log_admin("[key_name(usr)] toggled the win state for [current]'s objective: [objective.explanation_text]")
	else if (href_list["common"])
		switch(href_list["common"])
			if("undress")
				for(var/obj/item/W in current)
					current.dropItemToGround(W, TRUE) //The 1 forces all items to drop, since this is an admin undress.
	else if (href_list["obj_announce"])
		announce_objectives()

	//Something in here might have changed my mob
	if(self_antagging && (!usr || !usr.client) && current.client)
		usr = current
	traitor_panel()


/datum/mind/proc/get_all_objectives()
	var/list/all_objectives = list()
	for(var/datum/antagonist/A in antag_datums)
		all_objectives |= A.objectives
	return all_objectives

/datum/mind/proc/announce_objectives()
	var/obj_count = 1
	to_chat(current, span_notice("My current objectives:"))
	for(var/objective in get_all_objectives())
		var/datum/objective/O = objective
		O.update_explanation_text()
		to_chat(current, "<B>Objective #[obj_count]</B>: [O.explanation_text]")
		obj_count++


/datum/mind/proc/make_Traitor()
	if(!(has_antag_datum(/datum/antagonist/traitor)))
		add_antag_datum(/datum/antagonist/traitor)


/datum/mind/proc/AddSpell(obj/effect/proc_holder/spell/S)
	if(!S)
		return
	spell_list += S
	S.action.Grant(current)

/datum/mind/proc/check_learnspell()
	if(!has_spell(/obj/effect/proc_holder/spell/self/learnspell)) //are we missing the learning spell?
		if((spell_points - used_spell_points) > 0) //do we have points?
			AddSpell(new /obj/effect/proc_holder/spell/self/learnspell(null)) //put it in
			return

	if((spell_points - used_spell_points) <= 0) //are we out of points?
		RemoveSpell(/obj/effect/proc_holder/spell/self/learnspell) //bye bye spell
		return
	return

/datum/mind/proc/check_learnvampspellperk()
	if(!has_spell(/obj/effect/proc_holder/spell/self/learnvampspell)) //are we missing the learning spell?
		if((vamp_points - used_vamp_points) > 0) //do we have points?
			AddSpell(new /obj/effect/proc_holder/spell/self/learnvampspell(null)) //put it in
			return

	if((vamp_points - used_vamp_points) <= 0) //are we out of points?
		RemoveSpell(/obj/effect/proc_holder/spell/self/learnvampspell) //bye bye spell
		return
	return

/datum/mind/proc/has_spell(spell_type, specific = FALSE)
	if(istype(spell_type, /obj/effect/proc_holder))
		var/obj/instanced_spell = spell_type
		spell_type = instanced_spell.type
	for(var/obj/effect/proc_holder/spell as anything in spell_list)
		if((specific && spell.type == spell_type) || istype(spell, spell_type))
			return TRUE
	return FALSE

/datum/mind/proc/owns_soul()
	return soulOwner == src

//To remove a specific spell from a mind
/datum/mind/proc/RemoveSpell(obj/effect/proc_holder/spell/spell)
	if(!spell)
		return
	for(var/X in spell_list)
		var/obj/effect/proc_holder/spell/S = X
		if(istype(S, spell))
			spell_list -= S
			qdel(S)

/datum/mind/proc/RemoveAllSpells()
	for(var/obj/effect/proc_holder/S in spell_list)
		RemoveSpell(S)

/datum/mind/proc/transfer_martial_arts(mob/living/new_character)
	if(!ishuman(new_character))
		return
	if(martial_art)
		if(martial_art.base) //Is the martial art temporary?
			martial_art.remove(new_character)
		else
			martial_art.teach(new_character)

/datum/mind/proc/transfer_actions(mob/living/new_character)
	if(current && current.actions)
		for(var/datum/action/A in current.actions)
			A.Grant(new_character)
	transfer_mindbound_actions(new_character)

/datum/mind/proc/transfer_mindbound_actions(mob/living/new_character)
	for(var/X in spell_list)
		var/obj/effect/proc_holder/spell/S = X
		S.action.Grant(new_character)

/datum/mind/proc/disrupt_spells(delay, list/exceptions = New())
	for(var/X in spell_list)
		var/obj/effect/proc_holder/spell/S = X
		for(var/type in exceptions)
			if(istype(S, type))
				continue
		S.charge_counter = delay
		S.updateButtonIcon()
		INVOKE_ASYNC(S, TYPE_PROC_REF(/obj/effect/proc_holder/spell, start_recharge))

/datum/mind/proc/get_ghost(even_if_they_cant_reenter, ghosts_with_clients)
	for(var/mob/dead/observer/G in (ghosts_with_clients ? GLOB.player_list : GLOB.dead_mob_list))
		if(G.mind == src)
			if(G.can_reenter_corpse || even_if_they_cant_reenter)
				return G
			break

/datum/mind/proc/grab_ghost(force)
	var/mob/dead/observer/G = get_ghost(even_if_they_cant_reenter = force)
	. = G
	if(G)
		G.reenter_corpse()


/datum/mind/proc/has_objective(objective_type)
	for(var/datum/antagonist/A in antag_datums)
		for(var/O in A.objectives)
			if(istype(O,objective_type))
				return TRUE

/mob/proc/sync_mind()
	mind_initialize()	//updates the mind (or creates and initializes one if one doesn't exist)
	mind.active = 1		//indicates that the mind is currently synced with a client

/datum/mind/proc/has_martialart(string)
	if(martial_art && martial_art.id == string)
		return martial_art
	return FALSE

/mob/dead/new_player/sync_mind()
	return

/mob/dead/observer/sync_mind()
	return

//Initialisation procs
/mob/proc/mind_initialize()
	if(mind)
		mind.key = key

	else
		mind = new /datum/mind(key)
		SSticker.minds += mind
	if(!mind.name)
		mind.name = real_name
	mind.current = src

/mob/living/carbon/mind_initialize()
	..()
	last_mind = mind

//HUMAN
/mob/living/carbon/human/mind_initialize()
	..()
	if(!mind.assigned_role)
		mind.assigned_role = "Unassigned" //default

//AI
/mob/living/silicon/ai/mind_initialize()
	..()
	mind.assigned_role = "AI"

//BORG
/mob/living/silicon/robot/mind_initialize()
	..()
	mind.assigned_role = "Cyborg"

//PAI
/mob/living/silicon/pai/mind_initialize()
	..()
	mind.assigned_role = ROLE_PAI
	mind.special_role = ""

/datum/mind/proc/add_sleep_experience(skill, amt, silent = FALSE)
	sleep_adv.add_sleep_experience(skill, amt, silent)

