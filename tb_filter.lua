local tb = {}

---------------
--   Utils   --
---------------

-- check if a given file path exists
function tb.file_exists(file)
  local f = io.open(file, "rb")
  if f then f:close() end
  return f ~= nil
end

-- get all lines from a file, returns an empty 
-- list/table if the file does not exist
function tb.lines_from(file)
  if not tb.file_exists(file) then return {} end
  lines = {}
  for line in io.lines(file) do 
    lines[#lines + 1] = line
  end
  return lines
end

-- creates an indented string representation of nested tables
function tb.table_to_pretty_string(tbl, prefix)
	str_out = ""
	if prefix == nil then
		prefix = ""
	end
	for key, value in pairs(tbl) do
		str_out = str_out .. prefix .. tostring(key) .. ": "
		if type(value) == "table" then
			str_out = str_out .. "\n" .. tb.table_to_pretty_string(value, prefix.."  ")
		else
			str_out = str_out .. tostring(value) .. "\n"
		end
	end
	return str_out
end

-- helper function for printing log information to stdout
function tb.print_log(...)
    local n = select("#",...)
    for i = 1,n do
        local v = tostring(select(i,...))
        io.write(v)
        if i~=n then io.write' ' end
    end
    io.write'\n'
end

-- print informative messages
function tb.log_info(...)
	tb.print_log("[info ] ", ...)
end

-- print debug messages
function tb.log_debug(...)
	tb.print_log("[debug] ", ...)
end

-- print error messages
function tb.log_error(...)
	tb.print_log("[error] ", ...)
end

-- returns the mailbox name of a thunderbird url mailbox 
function tb.url_to_mailbox(url_str)
	return regex_search("imap:\\/\\/.*@.*?\\/(?:INBOX\\/)?(.*)", url_str)
end

-- performs thunderbird "mark seen" action
function tb.action_mark_seen(account, results, value)
	tb.log_info("Marking seen")
	results:mark_seen()
end

-- performs thunderbird "mark unseen" action
function tb.action_mark_unseen(account, results, value)
	tb.log_info("Marking unseen.")
	results:mark_unseen()
end

-- performs thunderbird "add tag" action
function tb.action_add_tag(account, results, value)
	tb.log_info("Adding tag: " .. value)
	results:add_flags({value})
end

-- performs thunderbird "mark flagged" action
function tb.action_mark_flagged(account, results, value)
	results:mark_flagged()
end

-- performs thunderbird "delete messages" action
function tb.action_delete_messages(account, reults, value)
	results:delete_messages()
end 

-- performs thunderbird "move to folder" action
function tb.action_move_to_folder(account, results, value)
	fnd_mbox, mbox_str = tb.url_to_mailbox(value)

	if not fnd_mbox then
		tb.log_info("Could not find mailbox. Ignoring Move to folder on " .. value)
		do return end
	end

	results:move_messages(account[mbox_str])
end

-- performs thunderbird "copy to folder" action
function tb.action_copy_to_folder(account, results, value)
	fnd_mbox, mbox_str = tb.url_to_mailbox(value)

	if not fnd_mbox then
		tb.log_info("Could not find mailbox. Ignoring Copy to folder on " .. value)
		do return end
	end

	results:copy_messages(account[mbox_str])
end

-- extracts parenthesized fields from thunderbird filter rule
function tb.parse_custom_field(field)
	fnd, match = regex_search("\\\\\"(.*)\\\\\"", field)
	return match
end

-- returns true if the string field contains a word in escaped quotes
function tb.is_custom_field(field)
	fnd, match = regex_search("\\\\\"(.*)\\\\\"", field)
	return fnd
end

-- applys a filter conditions which is based on a mail field
function tb.apply_field_condition(mailbox, field, condition, value)
	if condition == "contains" then
		results = mailbox:contain_field(field, value)
	elseif condition == "doesn't contain" then
		match_str = "^((?!" .. value .. ").)*$"
		results = mailbox:match_field(field, match_str)
	elseif condition == "is" then
		match_str = "(?i)^(.*<)?" .. value .. ">?$"
		results = mailbox:match_field(field, match_str)
	elseif condition == "isn't" then
		match_str = "(?i)^(.*<)?" .. value .. ">?$"
		results = mailbox:select_all() - mailbox:match_field(field, match_str)
	elseif condition == "begins with" then
		match_str = "(?i)^(.*<)?" .. value
		results = mailbox:match_field(field, match_str)
	elseif condition == "ends with" then
		match_str = "(?i)" .. value .. ">?$"
		results = mailbox:match_field(field, match_str)
	end
	return results
end

-- applys a filter conditions which is based on the messages' date
function tb.apply_date_condition(mailbox, field, condition, value)
	if condition == "is" then
		results = mailbox:arrived_on(value)
	elseif condition == "isn't" then
		results = mailbox:select_all() - mailbox:arrived_on(value)
	elseif condition == "is before" then
		results = mailbox:arrived_before(value)
	elseif condition == "is after" then
		results = mailbox:arrived_since(value)
	end
	return results
end

-- applys a filter condition which is based on the messages' status
function tb.apply_status_condition(mailbox, field, condition, value)
	if condition == "is" then
		if value == "replied" then
			results = mailbox:is_answered()
		elseif value == "read" then
			results = mailbox:is_seen()
		elseif value == "new" then
			results = mailbox:is_new()
		elseif value == "forwarded" then
			tb.log_error("Error: status is \"forwarded\" is not supported yet!")
			results = nil
		elseif value == "flagged" then
			results = mailbox:is_flagged()
		end
	elseif condition == "isn't" then
		if value == "replied" then
			results = mailbox:is_unanswered()
		elseif value == "read" then
			results = mailbox:is_unseen()
		elseif value == "new" then
			results = mailbox:is_old()
		elseif value == "forwarded" then
			tb.log_error("Error: status is \"forwarded\" is not supported yet!")
			results = nil
		elseif value == "flagged" then
			results = mailbox:is_unflagged()
		end
	end

	return results
end

-- applys a filter condition which is based on the messages' age
function tb.apply_age_in_days_condition(mailbox, field, condition, value)
	age = tonumber(value)
	date = form_date(age)
	tb.log_debug("Corresponding date is: " .. date)
	if condition == "is" then
		results = mailbox:arrived_on(date)
	elseif condition == "isn't" then
		results = mailbox:select_all() - mailbox:arrived_on(date)
	elseif condition == "is greater than" then
		results = mailbox:is_older(age)
	elseif condition == "is less than" then
		results = mailbox:is_newer(age)
	end

	return results
end

-- applys a filter condition which is based on the messages' size
function tb.apply_size_condition(mailbox, field, condition, value)
	size = tonumber(value)
	size = size*1024
	if condition == "is" then
		results = mailbox:is_larger(size-1) + mailbox:is_smaller(size+1)
	elseif condition == "is greater than" then
		results = mailbox:is_larger(size)
	elseif condition == "is less than" then
		results = mailbox:is_smaller(size)
	end

	return results
end

-- applys a filter condition which is based on the messages' tags
function tb.apply_tag_condition(mailbox, field, condition, value)
	if condition == "contains" then
		results = mailbox:has_keyword(value)
	elseif condition == "doesn't contain" then
		results = mailbox:has_unkeyword(value)
	elseif condition == "is" then
		tb.log_info("Tag \"is\"-operation not supported.")
		results = nil
	elseif condition == "isn't" then
		tb.log_info("Tag \"isn't\"-operation not supported.")
		results = nil
	elseif condition == "is empty" then
		tb.log_info("Tag \"is empty\"-operation not supported.")
		results = nil
	elseif condition == "isn't empty" then
		tb.log_info("Tag \"isn't empty\"-operation not supported.")
		results = nil
	end

	return results
end

-- applys a filter condition which is based on the messages' body
function tb.apply_body_condition(mailbox, field, condition, value)
	if condition == "contains" then
		results = mailbox:contain_body(value)
	elseif condition == "doesn't contain" then
		results = mailbox:select_all() - mailbox:contain_body(value)
	elseif condition == "is" then
		match_str = "(?i)^" .. value .. "$"
		results = mailbox:contain_body(value) -- Pre-filtering
		results = results:match_body(match_str)
	elseif condition == "isn't" then
		match_str = "(?i)^" .. value .. "$"
		results = mailbox:contain_body(value) -- Pre-filtering
		results = results:match_body(match_str)
		results = mailbox:select_all() - results
	end

	return results
end

-- applys a general thunderbird filter condition
function tb.apply_condition(mailbox, field, condition, value)
	if field == "from" or field == "subject" or field == "to" or field == "cc" then
		results = tb.apply_field_condition(mailbox, field, condition, value)
	elseif field == "to or cc" then
		results = tb.apply_condition(mailbox, "to", condition, value) +
				tb.apply_condition(mailbox, "cc", condition, value)
	elseif field == "all addresses" then
		results = tb.apply_condition(mailbox, "from", condition, value) + 
				tb.apply_condition(mailbox, "to", condition, value) + 
				tb.apply_condition(mailbox, "cc", condition, value) +
				tb.apply_condition(mailbox, "bcc", condition, value)
	elseif field == "date" then
		results = tb.apply_date_condition(mailbox, field, condition, value)
	elseif field == "age in days" then
		results = tb.apply_age_in_days_condition(mailbox, field, condition, value)
	elseif field == "size" then
		results = tb.apply_size_condition(mailbox, field, condition, value)
	elseif field == "tag" then
		results = tb.apply_tag_condition(mailbox, field, condition, value)
	elseif field == "body" then
		results = tb.apply_body_condition(mailbox, field, condition, value)
	elseif field == "priority" then
		tb.log_info("\"priority\"-condition not supported.")
		results = nil
	elseif tb.is_custom_field(field) then
		results = tb.apply_field_condition(mailbox, tb.parse_custom_field(field), condition, value)
	end

	return results
end

-- apply a table of thunderbird conditions
-- conditions is table of tables containing an operator(string), a field(string), a condition(string) and a value(string)
--[[
Apply a table of thunderbird conditions

Arguments:
mailbox (table) -> mailbox or imapfilter messages on which to apply the conditions
conditions (table) -> table of tables containing:
    operator(string) -> logical operator (AND or OR)
    field (string) -> which mail-field (eg. size, date, body) the filter operats on
    condition (string) -> the condition 
    values (string) -> the value of the condition
function tb.apply_conditions(mailbox, conditions)
	key, values = next(conditions, nil)
	tb.log_debug(unpack(values))
	operator, field, condition, value = unpack(values)
	filtered_msgs = tb.apply_condition(mailbox, field, condition, value)
	key, values = next(conditions, key)
	while key do
		tb.log_debug(unpack(values))
		operator, field, condition, value = unpack(values)
		results = tb.apply_condition(mailbox, field, condition, value)
		if operator == "AND" then
			filtered_msgs = filtered_msgs * results
		elseif operator == "OR" then
			filtered_msgs = filtered_msgs + results
		end
		key, values = next(conditions, key)
	end
	return filtered_msgs
end

--[[
Parses the thunderbird filter condition string

Arguments:
condition_string (string) -> value of the condition-keyword

Returns:
a table of tables each containt an operator(string, a filed(string), a condition(string) and a value(string)
]]--
function tb.parse_conditions(condition_string)
	regex_cmd = "((OR|AND) \\(.+?,.+?,.+?\\))"
	regex_args = "(?:OR|AND) \\((.+?),(.+?),(.+?)\\)"

	fnd, m1, operator = regex_search(regex_cmd, condition_string)
	conditions = {}
	while fnd do
		fnd_args, field, condition, value = regex_search(regex_args, m1)

		table.insert(conditions, {operator, field, condition, value})

		condition_string = string.sub(condition_string, string.len(m1))
		fnd, m1, operator = regex_search(regex_cmd, condition_string)
	end
	return conditions
end

--[[
Parses a single line of thunderbird's msgFilterRules.dat file

Arguments:
line (string) -> a single line of the filter rules

Returns:
is_well_formatted (boolean) -> true if the line is of the format key="value"
key (string) -> the filter keyword
value (string) -> the filter value
]]--
function tb.parse_filter_line(line)
	is_well_formatted, key, value = regex_search("(?m)^(.+?)=\\\"(.*)\\\"\\s*$", line)
	return is_well_formatted, key, value
end

--[[
returns whole filter description. table conataining:
name (string) -> name of filter
enabled (boolean) -> if filter is enabled
actions (table) -> table of all actions to use on filtered messages
condition (table) -> table containing the conditions
]]--
function tb.parse_filter_rules(filter_lines)
	rules = {}
	tmp_rule = {}
	tmp_actions = {}
	tmp_action = {}
	is_first_rule = true
	for key, line in pairs(filter_lines) do
		fnd, key, value = tb.parse_filter_line(line)
		if fnd then
			if key == "name" then
				if is_first_rule then
					tmp_rule["name"] = value
					is_first_rule = false
				else
					tmp_rule["actions"] = tmp_actions
					table.insert(rules, tmp_rule)
					tmp_rule = {}
					tmp_actions = {}
					tmp_rule["name"] = value
				end
			elseif key == "enabled" then
				if value == "yes" then
					tmp_rule["enabled"] = true
				else
					tmp_rule["enabled"] = false
				end
			elseif key == "action" then
				table.insert(tmp_actions, {value})
			elseif key == "actionValue" then
				table.insert(tmp_actions[#tmp_actions], value)
			elseif key == "condition" then
				conditions = tb.parse_conditions(value)
				tmp_rule["conditions"] = conditions
			end
		end
	end

	tmp_rule["actions"] = tmp_actions
	table.insert(rules, tmp_rule)
	return rules
end

--[[
applys a table of filter actions on the given messages
acc (table) -> imap account
actions (table) -> table of tables each containing an action(string) and a value(string)
msgs (table) -> a table of imapfilter messages on which to perform the actions
]]--
function tb.do_actions(acc, actions, msgs)
	for key, action_tbl in pairs(actions) do
		action, value = unpack(action_tbl)
		tb.log_debug(unpack({action, value}))
		if action == "Move to folder" then
			tb.action_move_to_folder(acc, msgs, value)
		elseif action == "Copy to folder" then
			tb.action_copy_to_folder(acc, msgs, value)
		elseif action == "Forward" then
			tb.log_info("Forwarding is not supported. Action ignored.")
		elseif action == "Mark unread" then
			tb.action_mark_unseen(acc, msgs, value)
		elseif action == "Mark read" then
			tb.action_mark_seen(acc, msgs, value)
		elseif action == "Mark flagged" then
			tb.action_mark_flagged(acc, msgs, value)
		elseif action == "Change priority" then
			tb.log_info("Priority is not supported. Action ignored.")
		elseif action == "AddTag" then
			tb.action_add_tag(acc, msgs, value)
		elseif action == "JunkScore" then
			tb.log_info("JunkScore not supported. Action ignored.")
		elseif action == "Delete" then
			tb.action_delete_messages(acc, msgs, value)
		elseif action == "Ignore thread" then
			tb.log_info("Ignore thread not supported. Action ignored.")
		elseif action == "Ignore subthread" then
			tb.log_info("Ignore subthread not supported. Action ignored.")
		elseif action == "Watch thread" then
			tb.log_info("Watch thread not supported. Action ignored.")
		elseif action == "Stop execution" then
			tb.log_info("Stop execution not supported. I will run forever...")
		end
	end
end

--[[
executes a thunderbird filter rules
account (table) -> account on which to perform the rules
target (table) -> mailbox or table of imapfilter messages on which to perform the rules
filter_rules (table) -> table of strings containing the msgFilterRules.dat content
]]--
function tb.execute_filters(account, target, filter_rules)
	for key, filter in pairs(filter_rules) do
		if filter["enabled"] then
			tb.log_info("Executing filter: " .. filter["name"])
			tb.log_info("----- Conditions -----")
			conditions = filter["conditions"]
			msgs = tb.apply_conditions(target, conditions)

			tb.log_info("----- Actions -----")
			actions = filter["actions"]
			tb.do_actions(account, actions, msgs)
		end
	end
end

--[[
Parses a thunderbird msgFilterRules.dat file and applys the filter rules
account (table) -> account on which to perform the rules
target (table) -> mailbox or table of imapfilter messages on which to perform the rules
file_name (string) -> path of a thunderbird msgFilterRules.dat file
]]--
function tb.do_thunderbird_filter(account, target, file_name)
        tb.log_info("Running thunderbird filters from: " .. file_name)
	lines = tb.lines_from(file_name)
	tbl = tb.parse_filter_rules(lines)
	tb.execute_filters(account, target, tbl)
end

return tb
