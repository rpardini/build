# global variables managing the state of the fragment manager. treat as private.
declare -A fragment_function_info                # maps a function name to a string with KEY=VALUEs information about the defining fragment
declare -i initialize_fragment_manager_counter=0 # how many times has the fragment manager initialized?

# This is a helper function for calling hooks.
# It follows the pattern long used in the codebase for hook-like behaviour:
#    [[ $(type -t name_of_hook_function) == function ]] && name_of_hook_function
# but with the following added behaviors:
# 1) it allows for many arguments, and will treat each as a hook point.
#    this allows for easily kept backwards compatibility when renaming hooks, for example.
# 2) it will read the stdin and assume it's documentation for the hook point.
#    combined with heredoc in the call site, it allows for inline documentation about the hook
# notice: this is not involved in how the hook functions came to be. read below for that.
call_hook_point() {
	# First, consume the stdin and write docs...
	write_hook_documentation_fragment "$@"
	# Then call the hooks, if they are defined as functions.
	for hook_name in "$@"; do
		# Log to the fragment log that the hook is starting...
		echo "-- hook being called: ${hook_name}" >>"${FRAGMENT_MANAGER_LOG_FILE}"
		# shellcheck disable=SC2086
		[[ $(type -t ${hook_name}) == function ]] && { ${hook_name}; }
	done
}

write_hook_documentation_fragment() {
	cat <<EOD >>"${FRAGMENT_MANAGER_DOCS_FILE}"
## Hook: \`$1\`
### Description
$(cat -)
### Names:
$(
		for hook_name in "$@"; do echo "- \`${hook_name}\`"; done
		echo ""
	)

EOD
}

# what this does is a lot of bash mumbo-jumbo to find all board-,family-,config- or user-defined hook points.
# it will then compose a full hook point (function) that calls all the implementing hooks.
# this centralized function will then be called by the regular Armbian build system, which is oblivious to how
# this function came to be.
# to avoid hardcoding the list of hook-points (eg: user_config, image_tweaks_pre_customize, etc) we use
# a marker in the function names, namely "__" (two underscores) to determine the hook point.
initialize_fragment_manager() {
	local hook_fragment_delimiter="__"

	export initialize_fragment_manager_counter=$((initialize_fragment_manager_counter + 1))

	# log whats happening.
	echo "-- initialize_fragment_manager() called; produced functions below." >>"${FRAGMENT_MANAGER_LOG_FILE}"

	# list all defined functions. filter only the ones that have the delimiter. get only the part before the delimiter.
	# sort them, and make them unique. the sorting is required for uniq to work, and does not affect the ordering of execution.
	# get them on a single line, space separated.
	local all_hook_points
	all_hook_points="$(compgen -A function | grep "${hook_fragment_delimiter}" | awk -F "${hook_fragment_delimiter}" '{print $1}' | sort | uniq | xargs echo -n)"

	declare -i hook_points_counter=0 hook_functions_counter=0 hook_point_functions_counter=0

	local FUNCTION_SORT_OPTIONS="--general-numeric-sort --ignore-case" #  --random-sort could be used to introduce chaos
	local hook_point=""
	# now loop over the hook_points.
	for hook_point in ${all_hook_points}; do
		echo "-- hook_point ${hook_point}" >>"${FRAGMENT_MANAGER_LOG_FILE}"

		# check if the hook point is already defined as a function.
		# that can happen for example with user_config(), that can be implemented itself directly by a userpatches config.
		# for now, just warn, but we could devise a way to actually integrate it in the call list.
		# or: advise the user to rename their user_config() function to something like user_config__make_it_awesome()
		local existing_hook_point_function
		existing_hook_point_function="$(compgen -A function | grep "^${hook_point}\$")"
		if [[ "${existing_hook_point_function}" == "${hook_point}" ]]; then
			echo "--- hook_point_functions (final sorted realnames): ${hook_point_functions}" >>"${FRAGMENT_MANAGER_LOG_FILE}"
			display_alert "Fragment conflict" "function ${hook_point} already defined, ignoring functions: ${hook_point_functions}" "wrn"
			continue
		fi

		# for each hook_point, obtain the list of implementing functions.
		# the sort order here is (very) relevant, since it determines final execution order.
		# so the name of the functions actually determine the ordering.
		local hook_point_functions hook_point_functions_pre_sort hook_point_functions_sorted_sortnames

		# gather the real names of the functions (after the delimiter).
		hook_point_functions_pre_sort="$(compgen -A function | grep "^${hook_point}${hook_fragment_delimiter}" | awk -F "${hook_fragment_delimiter}" '{print $2}' | xargs echo -n)"
		echo "--- hook_point_functions_pre_sort: ${hook_point_functions_pre_sort}" >>"${FRAGMENT_MANAGER_LOG_FILE}"

		# add "500_" to the names of function that do NOT start with a number.
		# keep a reference of the new names to the old names (we'll sort on the new, but invoke the old)
		declare -A hook_point_functions_sortname_to_realname
		declare -A hook_point_functions_realname_to_sortname
		for hook_point_function_realname in ${hook_point_functions_pre_sort}; do
			local sortname
			sortname="${hook_point_function_realname}"
			[[ ! $sortname =~ ^[0-9] ]] && sortname="500_${sortname}"
			hook_point_functions_sortname_to_realname[${sortname}]="${hook_point_function_realname}"
			hook_point_functions_realname_to_sortname[${hook_point_function_realname}]="${sortname}"
		done

		# actually sort the sortnames...
		# shellcheck disable=SC2086
		hook_point_functions_sorted_sortnames="$(echo "${hook_point_functions_realname_to_sortname[*]}" | tr " " "\n" | LC_ALL=C sort ${FUNCTION_SORT_OPTIONS} | xargs echo -n)"
		echo "--- hook_point_functions_sorted_sortnames: ${hook_point_functions_sorted_sortnames}" >>"${FRAGMENT_MANAGER_LOG_FILE}"

		# then map back to the real names, keeping the order..
		hook_point_functions=""
		for hook_point_function_sortname in ${hook_point_functions_sorted_sortnames}; do
			hook_point_functions="${hook_point_functions} ${hook_point_functions_sortname_to_realname[${hook_point_function_sortname}]}"
		done
		# shellcheck disable=SC2086
		hook_point_functions="$(echo -n ${hook_point_functions})"
		echo "--- hook_point_functions (final sorted realnames): ${hook_point_functions}" >>"${FRAGMENT_MANAGER_LOG_FILE}"

		hook_point_functions_counter=0
		hook_points_counter=$((hook_points_counter + 1))

		# determine the variables we'll pass to the hook function during execution.
		# this helps the fragment author create fragments that are portable between userpatches and official Armbian.
		local function_variables=""
		function_variables="HOOK_POINT=\"${hook_point}\""

		# loop over the functions for this hook_point (keep a total for the hook point and a grand running total)
		for hook_point_function in ${hook_point_functions}; do
			hook_point_functions_counter=$((hook_point_functions_counter + 1))
			hook_functions_counter=$((hook_functions_counter + 1))
		done
		function_variables="${function_variables} HOOK_POINT_TOTAL_FUNCS=\"${hook_point_functions_counter}\""

		echo "-- hook_point: ${hook_point} will run ${hook_point_functions_counter} functions: ${hook_point_functions}" >>"${FRAGMENT_MANAGER_LOG_FILE}"
		local temp_source_file_for_hook_point="${SRC}"/.tmp/fragment_function_definition.sh

		hook_point_functions_loop_counter=0

		# now compose a function definition. notice the heredoc. it will be written to tmp file, logged, then sourced.
		# theres a lot of opportunities here, but for now I keep it simple:
		# - execute functions in the order defined by ${hook_point_functions} above
		# - define call-specific environment variables, to help fragment authors to write portable fragments (eg: FRAGMENT_DIR)
		cat <<FUNCTION_DEFINITION_HEADER >"${temp_source_file_for_hook_point}"
		${hook_point}() {
			echo "*** Fragment-managed hook starting '${hook_point}': will run ${hook_point_functions_counter} functions: '${hook_point_functions}'" >>"\${FRAGMENT_MANAGER_LOG_FILE}"
FUNCTION_DEFINITION_HEADER

		for hook_point_function in ${hook_point_functions}; do
			hook_point_functions_loop_counter=$((hook_point_functions_loop_counter + 1))
			local hook_point_function_variables="${function_variables}" # start with common vars... (eg: HOOK_POINT_TOTAL_FUNCS)
			# add the contextual fragment info for the function (eg, FRAGMENT_DIR)
			hook_point_function_variables="${hook_point_function_variables} ${fragment_function_info["${hook_point}${hook_fragment_delimiter}${hook_point_function}"]}"
			# add the current execution counter, so the fragment author can know in which order it is being actually called
			hook_point_function_variables="${hook_point_function_variables} HOOK_ORDER=\"${hook_point_functions_loop_counter}\""
			# output the call, passing arguments, and also logging the output to the fragments log.
			# @TODO: better error handling. we have a stupendous opportunity to 'set -e' here, and 'set +e' after, so that fragment authors are encouraged to write error handling code
			cat <<FUNCTION_DEFINITION_CALL >>"${temp_source_file_for_hook_point}"
			display_alert "Hook ${hook_point} ${hook_point_functions_loop_counter}/${hook_point_functions_counter}" "${hook_point_function}" "info"
			echo "*** *** Fragment-managed hook starting ${hook_point_functions_loop_counter}/${hook_point_functions_counter} '${hook_point}${hook_fragment_delimiter}${hook_point_function}':" >>"\${FRAGMENT_MANAGER_LOG_FILE}"
			${hook_point_function_variables} ${hook_point}${hook_fragment_delimiter}${hook_point_function} "\$@" | tee -a "\${FRAGMENT_MANAGER_LOG_FILE}"
			echo "*** *** Fragment-managed hook finished ${hook_point_functions_loop_counter}/${hook_point_functions_counter} '${hook_point}${hook_fragment_delimiter}${hook_point_function}':" >>"\${FRAGMENT_MANAGER_LOG_FILE}"
FUNCTION_DEFINITION_CALL
		done

		cat <<FUNCTION_DEFINITION_FOOTER >>"${temp_source_file_for_hook_point}"
			echo "*** Fragment-managed hook ending '${hook_point}': completed." >>"\${FRAGMENT_MANAGER_LOG_FILE}"
		} # end ${hook_point}() function
FUNCTION_DEFINITION_FOOTER

		# unsets
		unset hook_point_functions hook_point_functions_sortname_to_realname hook_point_functions_realname_to_sortname

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

	# first a check, has the fragment manager already initialized? then it is too late to add_fragment()
	if [[ ${initialize_fragment_manager_counter} -gt 0 ]]; then
		echo "ERR: Fragment problem -- already initialized -- too late to add '${fragment_name}' by ${BASH_SOURCE[1]}" | tee -a "${FRAGMENT_MANAGER_LOG_FILE}"
		exit 2
	fi

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
	# @TODO: It would be very important to be able to show where the origin of the problem is (who called add_fragment?) but that is left for later.
	if [[ ! -f "${fragment_file}" ]]; then
		echo "ERR: Fragment problem -- cant find fragment '${fragment_name}' anywhere." | tee -a "${FRAGMENT_MANAGER_LOG_FILE}"
		return 1
	fi

	local before_function_list after_function_list new_function_list
	# store a list of existing functions at this point, before sourcing the fragment.
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
		echo "fragment: ${fragment_name} defined function ${newly_defined_function}" >>"${FRAGMENT_MANAGER_LOG_FILE}"
		fragment_function_info["${newly_defined_function}"]="FRAGMENT=\"${fragment_name}\" FRAGMENT_DIR=\"${fragment_dir}\" FRAGMENT_FILE=\"${fragment_file}\""
	done

	echo "Fragment activated '${fragment_name}': from ${fragment_file}" >>"${FRAGMENT_MANAGER_LOG_FILE}"
}

# Thank you, dear reviewer, for reading this long. You're a hero.
# For the insanity above to (maybe) make sense to anyone we need logging. Unfortunately,
# this runs super early (from compile.sh), and DEST is not defined yet; logs will still be moved away and compressed when this runs.
# We cheat. That's why it's hidden down here. Sorry ;-)
mkdir -p "${SRC}"/.tmp
export FRAGMENT_MANAGER_LOG_FILE="${SRC}/.tmp/fragments.log"

# globally initialize the fragments log.
echo "-- lib/fragments.sh included. addition logs will be below, followed by the debug generated by the initialize_fragment_manager() function." >"${FRAGMENT_MANAGER_LOG_FILE}"

# we also generate documentation about the hook points.
export FRAGMENT_MANAGER_DOCS_FILE="${SRC}/.tmp/fragment_auto_docs.md"
echo "# Armbian build system extensibility" >"${FRAGMENT_MANAGER_DOCS_FILE}"
