## Hooks

# A honeypot wishful hooking. To make sure the system works.
# This is exactly the kind of hooking this fragment is meant to detect.
# This will never run, and should be detected below, but is handled specially and ignored.
# Note: this will never run, since we (hopefully) don't have a hook_point called 'wishful_hooking_example'.
function wishful_hooking_example__this_will_never_run() {
	echo "WISHFUL HOOKING -- this will never run. I promise."
}

# Run super late, hopefully at the last possible moment.
function fragment_metadata_ready__999_detect_wishful_hooking() {
	declare -i found_honeypot_function=0

	# Loop over the defined functions' keys. Find the info about the call. If not found, warn the user.
	# shellcheck disable=SC2154 # hook-exported variable
	for one_defined_function in ${!defined_hook_point_functions[*]}; do
		local source_info defined_info line_info
		defined_info="${defined_hook_point_functions["${one_defined_function}"]}"
		source_info="${hook_point_function_trace_sources["${one_defined_function}"]}"
		# shellcheck disable=SC2154 # hook-exported variable
		line_info="${hook_point_function_trace_lines["${one_defined_function}"]}"
		if [[ "$source_info" != "" ]]; then
			# log to debug log. it's reassuring.
			echo "\$\$\$ Hook function stacktrace for '${one_defined_function}'" "$(parse_hook_point_call_stacktrace "${source_info}" "${line_info}") (${defined_info})" >> "${FRAGMENT_MANAGER_LOG_FILE}"
			if [[ "${DEBUG_HOOKS}" == "yes" ]]; then
				display_alert "Hook function stacktrace for '${one_defined_function}'" "$(parse_hook_point_call_stacktrace "${source_info}" "${line_info}")" "wrn"
			fi
			continue # found a caller, move on.
		fi

		# special handling for the honeypot function. it is supposed to be always detected as uncalled.
		if [[ "${one_defined_function}" == "wishful_hooking_example__this_will_never_run" ]]; then
			# we expect this wishful hooking, it is done on purpose below, to make sure this code works.
			found_honeypot_function=1
		else
			# unexpected wishful hooking. Log and wrn the user.
			echo "\$\$\$ Wishful hooking detected" "Function '${one_defined_function}' is defined (${defined_info}) but never called by the build." >> "${FRAGMENT_MANAGER_LOG_FILE}"
			display_alert "Wishful hooking detected" "Function '${one_defined_function}' is defined (${defined_info}) but never called by the build." "wrn"
		fi
	done

	if [[ $found_honeypot_function -lt 1 ]]; then
		display_alert "Wishful hook DETECTION FAILED" "detect-wishful-hooking is not working. Something is weird with the fragment system. Sorry." "wrn" | tee -a "${FRAGMENT_MANAGER_LOG_FILE}"
	fi
}

## Internal functions

parse_hook_point_call_stacktrace() {
	local sources_str="$1" # Give this ${BASH_SOURCE[@]}
	local lines_str="$2"   # And this # Give this ${BASH_LINENO[@]}
	local sources lines index final_stack=""
	IFS=' ' read -r -a sources <<<"${sources_str}"
	IFS=' ' read -r -a lines <<<"${lines_str}"
	for index in "${!sources[@]}"; do
		local source="${sources[index]}" line="${lines[index]}"
		# skip fragment infrastructure sources, these only pollute the trace and add no insight to users
		[[ ${source} == *fragment_function_definition.sh*  ]] && continue;
		[[ ${source} == *lib/fragments.sh*  ]] && continue;
		# relativize the source, otherwise too long to display
		source="${source#"${SRC}/"}"
		# add to the list
		arrow="$([[ "$final_stack" != "" ]] && echo "->")"
		final_stack="${source}:${line} ${arrow} ${final_stack} "
	done
	# output the result, no newline
	echo -n $final_stack
}
