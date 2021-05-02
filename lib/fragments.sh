# global variables managing the state of the fragment manager. treat as private.
declare -A fragment_function_info     # maps a function name to a string with info about the defining fragment
declare -A fragment_defined_functions # maps a fragment name to a list of functions defined in it # @TODO: populate
declare -A fragment_defined_variables # maps a fragment name to a list of variables exported in it # @TODO: populate

# what this does is a lot of bash mumbo-jumbo to find all board-,family-,config- or user-defined hook points.
# it will then compose a full hook point (function) that calls all the implementing hooks.
# this centralized function will then be called by the regular Armbian build system, which is oblivious to how
# this function came to be.
# to avoid hardcoding the list of hook-points (eg: user_config, image_tweaks_pre_customize, etc) we use
# a marker in the function names, namely "__" (two underscores) to determine the hook point.
initialize_fragment_manager() {
	local hook_fragment_delimiter="__"

	# log whats happening.
	echo "-- initialize_fragment_manager() called; produced functions below." >>"${FRAGMENT_MANAGER_LOG_FILE}"

	# list all defined functions. filter only the ones that have the delimiter. get only the part before the delimiter.
	# sort them, and make them unique. the sorting is required for uniq to work, and does not affect the ordering of execution.
	# get them on a single line, space separated.
	local all_hook_points
	all_hook_points="$(compgen -A function | grep "${hook_fragment_delimiter}" | awk -F "${hook_fragment_delimiter}" '{print $1}' | sort | uniq | xargs echo -n)"

	declare -i hook_points_counter=0 hook_functions_counter=0 hook_point_functions_counter=0

	local FUNCTION_SORT_OPTIONS="--ignore-case" #  --random-sort could be used to introduce chaos, and make sure fragments play well with each other via CI tests.
	local hook_point=""
	# now loop over the hook_points.
	for hook_point in ${all_hook_points}; do
		# for each hook_point, obtain the list of implementing functions.
		# the sort order here is (very) relevant, since it determines final execution order. @TODO: advanced stuff for ordering.
		# so the name of the functions actually determine the ordering.
		local hook_point_functions
		hook_point_functions="$(compgen -A function | grep "^${hook_point}${hook_fragment_delimiter}" | awk -F "${hook_fragment_delimiter}" '{print $2}' | sort ${FUNCTION_SORT_OPTIONS} | xargs echo -n)"

		# check if the hook point is already defined as a function.
		# that can happen for example with user_config(), that can be implemented itself directly by a userpatches config.
		# for now, just warn, but we could devise a way to actually integrate it in the call list.
		local existing_hook_point_function
		existing_hook_point_function="$(compgen -A function | grep "^${hook_point}\$")"
		if [[ "${existing_hook_point_function}" == "${hook_point}" ]]; then
			display_alert "Fragment conflict" "function ${hook_point} already defined, ignoring functions: ${hook_point_functions}" "wrn"
			continue
		fi

		hook_point_functions_counter=0
		hook_points_counter=$((hook_points_counter + 1))

		# determine the variables we'll pass to the hook function during execution.
		# this helps the fragment author create fragments that are portable between userpatches and official Armbian.
		local function_variables=""
		function_variables="HOOK_POINT=\"${hook_point}\""

		# loop over the functions for this hook_point.
		for hook_point_function in ${hook_point_functions}; do
			hook_point_functions_counter=$((hook_point_functions_counter + 1))
			hook_functions_counter=$((hook_functions_counter + 1))
		done

		display_alert "hook_point: ${hook_point}" "will run ${hook_point_functions_counter} functions: ${hook_point_functions}" "info" >>"${FRAGMENT_MANAGER_LOG_FILE}"
		local temp_source_file_for_hook_point="${SRC}"/.tmp/fragment_function_definition.sh

		# now compose a function definition. notice the heredoc. it will be written to tmp file, logged, then sourced.
		# theres a lot of opportunities here, but for now I keep it simple:
		# - execute functions in the order defined by ${hook_point_functions} above
		# - define call-specific environment variables, to help fragment authors to write portable fragments (eg: FRAGMENT_DIR)
		cat <<FUNCTION_DEFINITION_SOURCE | tr "\t" " " >"${temp_source_file_for_hook_point}"
		${hook_point}() {
			display_alert "Fragment-managed hook starting" "${hook_point}: will run ${hook_point_functions}" "wrn"
		$(
			for hook_point_function in ${hook_point_functions}; do
				function_variables="${function_variables} ${fragment_function_info["${hook_point}${hook_fragment_delimiter}${hook_point_function}"]} HOOK_POINT_FUNCTION=\"${hook_point_function}\""
				echo "		# call ${hook_point}${hook_fragment_delimiter}${hook_point_function}"
				echo "				${function_variables} ${hook_point}${hook_fragment_delimiter}${hook_point_function} \"\$@\""
				echo "		"
			done
		)
			display_alert "Fragment-managed hook ending" "${hook_point}: has run ${hook_point_functions}" "wrn"
		} # end ${hook_point}() function
FUNCTION_DEFINITION_SOURCE

		# log what was produced in our own debug logfile
		#[[ -f /usr/bin/pygmentize ]] && /usr/bin/pygmentize "${temp_source_file_for_hook_point}" >>"${FRAGMENT_MANAGER_LOG_FILE}"
		cat "${temp_source_file_for_hook_point}" >>"${FRAGMENT_MANAGER_LOG_FILE}"

		# source the generated function.
		# shellcheck disable=SC1090
		source "${temp_source_file_for_hook_point}"

		rm -f "${temp_source_file_for_hook_point}"
	done
	display_alert "Fragment manager" "processed ${hook_points_counter} hook points and ${hook_functions_counter} hook functions" "info" | tee -a "${FRAGMENT_MANAGER_LOG_FILE}"
}

# process everything that happened during fragment related activities
# and write it to the log. also, move the log from the .tmp dir to its
# final location. # @TODO: call it!
finish_fragment_manager() {
	# Move temporary log file over to final destination, and start writing to it instead.
	mv -v "${FRAGMENT_MANAGER_LOG_FILE}" "${DEST}"/debug/fragments.log
	export FRAGMENT_MANAGER_LOG_FILE="${DEST}"/debug/fragments.log
}

# can be called by board, family, config or user to make sure a fragment is included.
# single argument is the fragment name.
# will look for it in /userpatches/fragments first.
# if not found there will look in /fragments
# if not found will throw and abort compilation (or will it? no set -e no this codebase in general)
add_fragment() {
	local fragment_name="$1"

	local fragment_dir
	local fragment_file
	local fragment_file_in_dir
	local fragment_floating_file

	# there are many opportunities here. too many, actually. let userpatches override just some functions, etc.
	for fragment_base_path in "${SRC}/userpatches/fragments" "${SRC}/fragments"; do
		fragment_dir="${fragment_base_path}/${fragment_name}"
		fragment_file_in_dir="${fragment_dir}/${fragment_name}.sh"
		fragment_floating_file="${fragment_base_path}/${fragment_name}.sh"

		if [[ -d "${fragment_dir}" ]] && [[ -f "${fragment_file_in_dir}" ]]; then
			fragment_file="${fragment_file_in_dir}"
			break
		elif [[ -f "${fragment_floating_file}" ]]; then
			fragment_dir="${fragment_base_path}" # this is misleading. only directory-based fragments should have this.
			fragment_file="${fragment_floating_file}"
			break
		fi
	done

	# After that, we should either have fragment_file and fragment_dir, or throw, since we can't find the fragment.
	# It would be very important to be able to show where the origin of the problem is (who called add_fragment?) but that is left for later.
	if [[ ! -f "${fragment_file}" ]]; then
		display_alert "Fragment problem" "cant find fragment '${fragment_name}' anywhere." "err" | tee -a "${FRAGMENT_MANAGER_LOG_FILE}"
		return 1
	fi

	# store a list of existing functions at this point, before sourcing the fragment.
	local before_function_list
	local after_function_list
	local new_function_list

	before_function_list="$(compgen -A function)"

	# source the file. fragments are not supposed to do anything except export variables and define functions, so nothing should happen here.
	# there is no way to enforce it though.
	# we could punish the fragment authors who violate it by removing some essential variables temporarily from the environment during this source, and restore them later.
	# shellcheck disable=SC1090
	. "${fragment_file}"

	# get a new list of functions after sourcing the fragment
	after_function_list="$(compgen -A function)"

	# compare before and after, thus getting the functions defined by the fragment.
	# comm is oldskool. we like it. go "man comm" to understand -13 below
	new_function_list="$(comm -13 <(echo "$before_function_list") <(echo "$after_function_list"))"

	# iterate over defined functions, store them in global associative array fragment_function_info
	for newly_defined_function in ${new_function_list}; do
		display_alert "fragment: ${fragment_name}" "defined function ${newly_defined_function}" "info" >>"${FRAGMENT_MANAGER_LOG_FILE}"
		fragment_function_info["${newly_defined_function}"]="FRAGMENT=\"${fragment_name}\" FRAGMENT_DIR=\"${fragment_dir}\" FRAGMENT_FILE=\"${fragment_file}\""
	done

	display_alert "Fragment activated" "'${fragment_name}': from ${fragment_file}" "info" >>"${FRAGMENT_MANAGER_LOG_FILE}"
}

# Thank you, dear reviewer, for reading this long. You're a hero.
# For the insanity above to (maybe) make sense to anyone we need logging. Unfortunately,
# this runs super early (from compile.sh), and DEST is not defined yet; logs will still be moved away and compressed when this runs.
# We cheat. That's why it's hidden down here. Sorry ;-)
mkdir -p "${SRC}"/.tmp
export FRAGMENT_MANAGER_LOG_FILE="${SRC}/.tmp/fragments.log"

# globally initialize the fragments log.
echo "-- lib/fragments.sh included. addition logs will be below, followed by the debug generated by the initialize_fragment_manager() function." >"${FRAGMENT_MANAGER_LOG_FILE}"
