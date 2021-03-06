dofile("table_show.lua")
dofile("urlcode.lua")
local urlparse = require("socket.url")
local http = require("socket.http")
JSON = (loadfile "JSON.lua")()

local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')
local item_type = nil
local item_name = nil
local item_value = nil

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false
local exitgrab = false
local exit_url = false
local retry_url = false

local outlinks = {}
local discovered = {}
local discovered_all = {}
local discovered_count = 0

local allowed_urls = {}

local bad_items = {}

local sort_type = nil
local intl = nil
local languages = {}

if not urlparse or not http then
  io.stdout:write("socket not corrently installed.\n")
  io.stdout:flush()
  abortgrab = true
end

local ids = {}

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

for lang in io.open("languages", "r"):lines() do
  languages[lang] = true
end

abort_item = function(abort)
  --if abort then
    abortgrab = true
  --end
  exitgrab = true
  if not bad_items[item_name] then
    io.stdout:write("Aborting item " .. item_name .. ".\n")
    io.stdout:flush()
    bad_items[item_name] = true
  end
end

write_message = function(s)
  io.stdout:write(s)
  io.stdout:flush()
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

submit_discovered = function()
  write_message("Submitting " .. tostring(discovered_count) .. " items.\n")
  for key, table in pairs({
    ["yahooanswers2-avt8l5qey8tzzf3"]=discovered,
    ["urls-jzgws2r0z10phee"]=outlinks
  }) do
    local items = nil
    for item, _ in pairs(table) do
      if not items then
        items = item
      else
        items = items .. "\0" .. item
      end
    end
    if items then
      local tries = 0
      while tries < 10 do
        local body, code, headers, status = http.request(
          "http://blackbird.arpa.li:23038/" .. key .. "/",
          items
        )
        if code == 200 or code == 409 then
          break
        end
        write_message("Could not queue items.\n")
        os.execute("sleep " .. math.floor(math.pow(2, tries)))
        tries = tries + 1
      end
      if tries == 10 then
        abort_item()
      end
    end
  end
  discovered = {}
  outlinks = {}
  discovered_count = 0
end

discover_item = function(type_, value, target)
  local item = nil
  if not target then
    target = "yahooanswers"
  end
  if target == "yahooanswers" then
    item = type_ .. ":" .. value
    target = discovered
  elseif target == "urls" then
    item = ""
    for c in string.gmatch(value, "(.)") do
      local b = string.byte(c)
      if b < 32 or b > 126 then
        c = string.format("%%%02X", b)
      end
      item = item .. c
    end
    target = outlinks
  else
    write_message("Bad items target.\n")
    abort_item()
  end
  if item == item_name or discovered_all[item] then
    return true
  end
  print('discovered item', item)
  target[item] = true
  discovered_all[item] = true
  discovered_count = discovered_count + 1
  if discovered_count == 100 then
    return submit_discovered()
  end
  return true
end

allowed = function(url, parenturl)
  if allowed_urls[url] then
    return true
  end

  if string.match(url, "^https?://[^/]*answers%.yahoo%.com/rss/question%?qid=")
    or string.match(url, "^https?://[^/]*answers%.yahoo%.com/amp/qna/") then
    return false
  end

  local tested = {}
  for s in string.gmatch(url, "([^/]+)") do
    if not tested[s] then
      tested[s] = 0
    end
    if tested[s] == 6 then
      return false
    end
    tested[s] = tested[s] + 1
  end

  local match = string.match(url, "[%?&]qid=([0-9a-zA-Z_%-]+)")
  if match then
    discover_item("qid", match)
  end
  match = string.match(url, "/activity/questions%?show=([0-9a-zA-Z_%-]+)")
  if match then
    discover_item("kid", match)
  end
  match = string.match(url, "/dir/index%?sid=([0-9]+)")
  if match then
    discover_item("dir", match)
  end

  if string.match(url, "^https?://[^%.]+%.answers%.yahoo%.com/") then
    return false
  end

  for _, pattern in pairs({"([0-9a-zA-Z]+)", "([0-9]+)"}) do
    for s in string.gmatch(url, pattern) do
      if ids[s] then
        return true
      end
    end
  end

  return false
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local parenturl = parent["url"]
if true then return false end

  url = string.gsub(url, ";jsessionid=[0-9A-F]+", "")

  if downloaded[url] or addedtolist[url] then
    return false
  end

  if allowed(url) or urlpos["link_expect_html"] == 0 then
    addedtolist[url] = true
    return true
  end
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil

  if is_css then
    return urls
  end
  
  downloaded[url] = true

  local function check(urla)
    local origurl = url
    local url = string.match(urla, "^([^#]+)")
    local url_ = string.match(url, "^(.-)%.?$")
    url_ = string.gsub(url_, "&amp;", "&")
    url_ = string.gsub(url_, ";jsessionid=[0-9A-F]+", "")
    local match = string.match(url_, "^(.+/showEvent.*[%?&])next=[^%?&]+[%?&]?")
    if match then
      url_ = match
    end
    url_ = string.match(url_, "^(.-)%s*$")
    url_ = string.match(url_, "^(.-)%??$")
    url_ = string.match(url_, "^(.-)&?$")
    --url_ = string.match(url_, "^(.-)/?$")
    url_ = string.match(url_, "^(.-)\\?$")
    if (downloaded[url_] ~= true and addedtolist[url_] ~= true)
      and allowed(url_, origurl) then
      table.insert(urls, { url=url_ })
      addedtolist[url_] = true
      addedtolist[url] = true
    end
  end

  local function checknewurl(newurl)
    if string.match(newurl, "^/>")
      or string.match(newurl, "^/&gt;")
      or string.match(newurl, "^/<")
      or string.match(newurl, "^/&lt;")
      or string.match(newurl, "^/%*") then
      return false
    end
    if string.match(newurl, "\\[uU]002[fF]") then
      return checknewurl(string.gsub(newurl, "\\[uU]002[fF]", "/"))
    end
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"))
    elseif string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^\\/") then
      checknewurl(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^//") then
      check(urlparse.absolute(url, newurl))
    elseif string.match(newurl, "^/") then
      check(urlparse.absolute(url, newurl))
    elseif string.match(newurl, "^%.%./") then
      if string.match(url, "^https?://[^/]+/[^/]+/") then
        check(urlparse.absolute(url, newurl))
      else
        checknewurl(string.match(newurl, "^%.%.(/.+)$"))
      end
    elseif string.match(newurl, "^%./") then
      check(urlparse.absolute(url, newurl))
    end
  end

  local function checknewshorturl(newurl)
    if string.match(newurl, "^%?") then
      check(urlparse.absolute(url, newurl))
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
      or string.match(newurl, "^[/\\]")
      or string.match(newurl, "^%./")
      or string.match(newurl, "^[jJ]ava[sS]cript:")
      or string.match(newurl, "^[mM]ail[tT]o:")
      or string.match(newurl, "^vine:")
      or string.match(newurl, "^android%-app:")
      or string.match(newurl, "^ios%-app:")
      or string.match(newurl, "^%${")) then
      check(urlparse.absolute(url, newurl))
    end
  end

  local function jg(json, location) -- json_get
    for _, s in pairs(location) do
      if not json or json[s] == nil then
        write_message("Could not find key " .. s .. " in " .. JSON:encode(json) .. ".\n")
        abort_item()
        return false
      end
      json = json[s]
    end
    return json
  end

  local function reservice(data)
    if true then
      return nil
    end
    data = JSON:encode(data)
    local base_url = string.match(url, "^(https?://[^/]+)")
    if not string.match(base_url, "//answers%.yahoo%.com$") then
      return nil
    end
    local identification = base_url .. data
    if not addedtolist[identification] then
      print("PUT", base_url, data)
      table.insert(urls, {
        url=base_url .. "/_reservice_/",
        method="PUT",
        body_data=data,
        headers={
          ["Content-Type"]="application/json"
        }
      })
      addedtolist[identification] = true
    end
  end

  local function question_answers(start, num, qid, lang, sort)
    if qid == item_value then
      reservice({
        type="CALL_RESERVICE",
        payload={
          qid=item_value,
          count=num,
          start=start,
          lang=lang,
          sortType=sort
        },
        reservice={
          name="FETCH_QUESTION_ANSWERS_END",
          start="FETCH_QUESTION_ANSWERS_START",
          state="CREATED"
        },
        kvPayload={
          key=qid,
          kvActionPrefix="KV/questionAnswers/"
        }
      })
    end
  end

  local function user_questions(start, count, euid, relation)
    reservice({
      type="CALL_RESERVICE",
      payload={
        relation=relation,
        start=start,
        count=count,
        euid=euid
      },
      reservice={
        name="FETCH_USER_QUESTIONS_END",
        start="FETCH_USER_QUESTIONS_START",
        state="CREATED"
      },
      kvPayload={
        key=relation,
        kvActionPrefix="KV/userQuestions/"
      }
    })
  end

  local function user_network(start, count, euid, network_type)
    data = {
      type="CALL_RESERVICE",
      payload={
        euid=euid,
        networkType=network_type,
        count=count
      },
      reservice={
        name="FETCH_USER_NETWORK_END",
        start="FETCH_USER_NETWORK_START",
        state="CREATED"
      },
      kvPayload={
        key=network_type,
        kvActionPrefix="KV/userNetwork/"
      }
    }
    if start ~= nil then
      data["payload"]["start"] = start
    end
    reservice(data)
  end

  local function set_intl(s)
    if s == "e1" then
      s = "espanol"
    elseif s == "my" then
      s = "malaysia"
    end
    if s == "us" or languages[s] then
      intl = s
    end
  end

  local a, b = string.match(url, "^(https?://s%.yimg%.com/.+/[0-9a-f]+)_[A-Z](%.[0-9a-zA-Z]+)$")
  if a and b then
    for _, c in pairs({"A", "C"}) do
      local newurl = a .. "_" .. c .. b
      allowed_urls[newurl] = true
      check(newurl)
    end
  end

  if string.match(url, "^https?://[^/]*yimg%.com/.+_192sq%.") then
    local newurl = string.gsub(url, "_192sq", "")
    allowed_urls[newurl] = true
    checknewurl(newurl)
  end

  if (allowed(url, nil) and status_code == 200)
    or string.find(url, "/_reservice_/") then
    html = read_file(file)
    if string.find(html, "emptyStream")
      or string.find(html, "ErrorState")
      or (
        string.match(url, "[%?&]qid=")
        and (
          not string.find(html, 'data%-icon="bookmark"')
          or not string.find(html, 'data%-icon="flag"')
          or not string.find(html, "QuestionActionBar")
          or not string.find(html, "M10%.414 18%.956c5%.992%.574 10%.588%-3%.19 10%.588%-7%.537 0%-4%.09%-4%.039%-7%.417%-9%.004%-7%.417%-4%.963 0%-9 3%.327%-9")
          or not string.find(html, "M6%.997 3l%.006 3h9%.995V3h%-10zm5 14%.165l5 2%.953V8h%-10v12%.117l5%-2%.952zm%.005 2%.508L6%.5 22%.863c%-%.667%.388%-1%.5%-%.096%-1%.5%-%.87V2%.006C5")
          or not string.find(html, "M40 10H28%.62l%-2%.888%-5%-%.008%.004C25%.38 4%.407 24%.74 4 24 4H8c%-1%.105 0%-2 %.896%-2 2v36c0")
          or not string.find(html, "<!%-%- %-%->")
          or not string.find(html, "Question__userName")
          or not string.find(html, '<div id="ans%-posting%-card%-' .. item_value .. '"></div>')
        )
      ) then
      write_message("Bad response content.\n")
      abort_item()
    end
    if item_type == "kid"
      and string.match(url, "^https?://[^/]*answers%.yahoo%.com/activity/questions%?show=") then
      local data = string.match(html, 'data%-state="({.-})">')
      data = JSON:decode(string.gsub(data, "&quot;", '"'))
      local profile_user = jg(data, {"profile", "profileUser"})
      if jg(profile_user, {"kid"}) ~= item_value then
        write_message("Wrong kid found on webpage.\n")
        abort_item()
      end
      euid = jg(profile_user, {"euid"})
      if not euid then
        write_message("No euid found.\n")
        abort_item()
      end
      set_intl(string.lower(string.match(jg(profile_user, {"lang"}), "([^%-]+)$")))
      if not intl then
        write_message("Language not found.\n")
        abort_item()
      end
      for _, question in pairs(jg(data, {"userQuestionsList", "ASKED", "questions"})) do
        if not string.find(html, "/question/index%?qid=" .. jg(question, {"qid"})) then
          write_message("Question content not in HTML.\n")
          abort_item()
        end
      end
      user_questions(1, 20, euid, "ASKED")
      user_questions(1, 20, euid, "ANSWERED")
      user_questions(1, 20, euid, "FOLLOWING")
      user_network(nil, 20, euid, "contacts")
      user_network(nil, 20, euid, "followers")
      reservice({
        type="CALL_RESERVICE",
        payload={
          euid=euid
        },
        reservice={
          name="FETCH_USER_INFO_END",
          start="FETCH_USER_INFO_START",
          state="CREATED"
        },
        kvPayload={
          key=euid,
          kvActionPrefix="KV/queriedUsers/"
        }
      })
    end
    if item_type == "qid"
      and string.match(url, "^https://[^/]*answers%.yahoo%.com/question/index%?qid=") then
      local data = string.match(html, 'data%-state="({.-})">')
      data = JSON:decode(string.gsub(data, "&quot;", '"'))
      if jg(data, {"question", "qid"}) ~= item_value then
        write_message("Wrong qid found on webpage.\n")
        abort_item()
      end
      --[[local question_count = 0
      for s in string.gmatch(html, '"/question/index%?qid=([0-9a-zA-Z]+)"') do
        if s ~= item_value then
          question_count = question_count + 1
        end
      end
      local min_questions = 1
      if question_count < min_questions then
        write_message("Found bad number of related questions at " .. tostring(question_count) .. ".\n")
        abort_item()
      end]]
      set_intl(jg(data, {"question", "intl"}))
      local lang = jg(data, {"question", "lang"})
      local answer_count = jg(data, {"question", "answerCount"})
      if answer_count > 0 then
        --[[for _, sort in pairs({"RELEVANCE", "RATING", "OLDEST", "NEWEST"}) do
          question_answers(1, 20, item_value, lang, sort)
        end]]
        local answers_list = jg(data, {"questionAnswersList", item_value})
        if not answers_list then
          write_message("Incomplete JSON data.\n")
          abort_item()
        end
        local questions_count = 0
        for _, answer_data in pairs(jg(answers_list, {"answers"})) do
          questions_count = questions_count + 1
          if not jg(answer_data, {"isAnonymous"}) then
            local kid = jg(answer_data, {"answerer", "kid"})
            if not string.find(html, 'href="/activity/questions%?show=' .. kid .. '"') then
              write_message("Answer content not in HTML.\n")
              abort_item()
            end
          end
        end
        local page_answers_count = jg(answers_list, {"count"})
        local flags_count = nil
        if questions_count ~= page_answers_count then
          flags_count = 0
          for _ in string.gmatch(html, 'data%-icon="flag"') do
            flags_count = flags_count + 1
          end
          if flags_count - 1 ~= page_answers_count then
            write_message("Unexpected number of answers found.\n")
            abort_item()
          end
        end
        if (page_answers_count < 10 or answer_count < 11)
          and page_answers_count ~= answer_count
          and not (flags_count ~= nil and page_answers_count - 1 == answer_count) then
          write_message("All answers should be on the webpage.\n")
          abort_item()
        end
        if answer_count > 10 then
          sort_type = jg(answers_list, {"sortType"})
          question_answers(1, 10, item_value, lang, sort_type)
          question_answers(11, 20, item_value, lang, sort_type)
        end
      end
      reservice({
        type="CALL_RESERVICE",
        payload={
          qid=item_value,
          lang=lang
        },
        reservice={
          name="FETCH_EXTRA_QUESTION_LIST_END",
          start="FETCH_EXTRA_QUESTION_LIST_START",
          state="CREATED"
        }
      })
    end
    if string.find(url, "/_reservice_/") then
      local data = JSON:decode(html)
      local payload_count = 0
      for _ in pairs(jg(data, {"payload"})) do
        payload_count = payload_count + 1
      end
      if jg(data, {"error"}) then
        write_message("Bad /_reservice_/ response.\n")
        abort_item()
      end
      local reservice_type = jg(data, {"type"})
      if payload_count == 0
        and reservice_type ~= "FETCH_EXTRA_QUESTION_LIST_END" then
        write_message("Empty payload!\n")
        abort_item()
      end
      if reservice_type == "FETCH_EXTRA_QUESTION_LIST_END" then
        local lang = jg(data, {"reservice", "previous_action", "payload", "lang"})
        if payload_count ~= 3 then
          if intl == "tw" or intl == "th" or intl == "hk" then
            return urls
          end
          write_message("Expected payload size 3, got " .. tostring(payload_count) .. ".\n")
          return urls
          --abort_item()
        end
        --[[for _, d in pairs(jg(data, {"payload"})) do
          reservice({
            type="CALL_RESERVICE",
            payload={
              qid=jg(d, {"qid"})
            },
            reservice={
              name="FETCH_QUESTION_END",
              start="FETCH_QUESTION_START",
              state="CREATED"
            },
            kvPayload={
              key=jg(d, {"qid"}),
              kvActionPrefix="KV/question/"
            }
          })
          reservice({
            type="CALL_RESERVICE",
            payload={
              count=10,
              lang=lang,
              qid=jg(d, {"qid"}),
              sortType=sort_type
            },
            reservice={
              name="FETCH_QUESTION_ANSWERS_END",
              start="FETCH_QUESTION_ANSWERS_START",
              state="CREATED"
            },
            kvPayload={
              key=jg(d, {"qid"}),
              kvActionPrefix="KV/questionAnswers/"
            }
          })
        end]]
      elseif reservice_type == "FETCH_USER_INFO_END" then
        local newurl = jg(data, {"payload", "imageUrl"})
        allowed_urls[newurl] = true
        checknewurl(newurl)
      elseif reservice_type == "FETCH_QUESTION_ANSWERS_END"
        or reservice_type == "FETCH_USER_QUESTIONS_END"
        or reservice_type == "FETCH_USER_NETWORK_END" then
        local orig_count = jg(data, {"reservice", "previous_action", "payload", "count"})
        local orig_start = jg(data, {"reservice", "previous_action", "payload"})
        if reservice_type ~= "FETCH_USER_NETWORK_END" then
          orig_start = jg(orig_start, {"start"})
        else
          orig_start = orig_start["start"]
        end
        if item_type == "kid"
          or (
            jg(data, {"reservice", "previous_action", "payload", "qid"}) == item_value
            and orig_count ~= 10
          ) then
          if item_type == "kid"
            and data["payload"]["apiError"]
            and data["payload"]["status"] == 403 then
            return urls
          end
          local payload_count = jg(data, {"payload", "count"})
          local payload_count_actual = 0
          local payload_list = nil
          if reservice_type == "FETCH_QUESTION_ANSWERS_END" then
            payload_list = jg(data, {"payload", "answers"})
          elseif reservice_type == "FETCH_USER_QUESTIONS_END" then
            payload_list = jg(data, {"payload", "questions"})
          elseif reservice_type == "FETCH_USER_NETWORK_END" then
            payload_list = jg(data, {"payload", "users"})
          else
            write_message("Unexpected reservice type.\n")
            abort_item()
          end
          for _ in pairs(payload_list) do
            payload_count_actual = payload_count_actual + 1
          end
          if payload_count_actual ~= payload_count then
            write_message("Expected " .. tostring(payload_count) .. " answers, got " .. tostring(payload_count_actual) .. " answers.\n")
            if payload_count - 1 ~= payload_count_actual then
              abort_item()
            end
          end
          if reservice_type == "FETCH_QUESTION_ANSWERS_END" then
            local payload_start = jg(data, {"payload", "start"})
            if payload_start ~= orig_start then
              write_message("Bad answers payload start.\n")
              abort_item()
            end
            if jg(data, {"payload", "qid"}) ~= item_value then
              write_message("Bad qid in JSON response.\n")
              abort_item()
            end
            local new_start = payload_start + payload_count
            local lang = jg(data, {"reservice", "previous_action", "payload", "lang"})
            local sort = jg(data, {"reservice", "previous_action", "payload", "sortType"})
            if jg(data, {"payload", "count"}) == orig_count then
              question_answers(new_start, orig_count, jg(data, {"payload", "qid"}), lang, sort)
            elseif new_start - 1 ~= jg(data, {"payload", "answerCount"}) then
              write_message("/_reservice_/ did not return all answers.\n")
              abort_item()
            end
          else
            local euid = jg(data, {"reservice", "previous_action", "payload", "euid"})
            if reservice_type == "FETCH_USER_QUESTIONS_END" then
              if payload_count > 0 then
                user_questions(
                  orig_start + payload_count,
                  orig_count,
                  euid,
                  jg(data, {"reservice", "previous_action", "payload", "relation"})
                )
              end
            elseif reservice_type == "FETCH_USER_NETWORK_END" then
              if orig_start == nil then
                orig_start = 1
              end
              if payload_count > 0 then
                user_network(
                  orig_start + payload_count,
                  orig_count,
                  euid,
                  jg(data, {"reservice", "previous_action", "payload", "networkType"})
                )
              end
            end
          end
        end
      end
    end
    html = string.gsub(html, "&quot;", '"')
    html = string.gsub(html, "&#039;", "'")
    if string.match(html, '"[^"]*captcha[^"]*"%s*:%s*true') then
      write_message("Something is up with recaptcha here!.\n")
      abort_item()
    end
    if string.match(html, '"payload"%s*:%s*%[%]')
      or string.match(html, '"payload"%s*:%s*{}') then
      write_message("Incomplete JSON data.\n")
      abort_item()
    end
    for s in string.gmatch(html, '"qid"%s*:%s*"([0-9a-zA-Z_%-]+)"') do
      discover_item("qid", s)
    end
    for s in string.gmatch(html, '"kid"%s*:%s*"([0-9a-zA-Z_%-]+)"') do
      discover_item("kid", s)
    end
    for newurl in string.gmatch(html, '"attached[iI]mage[uU]rl"%s*:%s*"([^"]+)"') do
      allowed_urls[newurl] = true
      checknewurl(newurl)
    end
    for _, variable in pairs({"text", "reference"}) do
      for s in string.gmatch(html, '"' .. variable .. '"%s*:%s*"([^"]+)"') do
        for newurl in string.gmatch(s, "(https?://[^%s\\%)]+)") do
          discover_item(nil, newurl, "urls")
        end
      end
    end
    for newurl in string.gmatch(html, '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ':%s*url%(([^%)"]+)%)') do
      checknewurl(newurl)
    end
  end

  if item_type == "qid" then
    for lang, _ in pairs(languages) do
      check("https://" .. lang .. ".answers.yahoo.com/question/index?qid=" .. item_value)
    end
  end

  return urls
end

set_new_item = function(url)
  local match = string.match(url, "^https?://answers%.yahoo%.com/question/index%?qid=([0-9a-zA-Z]+)$")
  local type_ = "qid"
  if not match then
    match = string.match(url, "^https?://answers%.yahoo%.com/activity/questions%?show=([0-9a-zA-Z]+)$")
    type_ = "kid"
  end
  if not match then
    match = string.match(url, "^https?://answers%.yahoo%.com/dir/index?sid=([0-9]+)$")
    type_ = "dir"
  end
  if match and not ids[match] then
    abortgrab = false
    exitgrab = false
    retry_url = false
    sort_type = nil
    intl = nil
    ids[match] = true
    item_value = match
    item_type = type_
    item_name = type_ .. ":" .. match
    io.stdout:write("Archiving item " .. item_name .. ".\n")
    io.stdout:flush()
  end
end

wget.callbacks.write_to_warc = function(url, http_stat)
  set_new_item(url["url"])
  retry_url = false
  if exitgrab
    or http_stat["statcode"] == 0
    or http_stat["statcode"] == 500
    or http_stat["statcode"] == 503
    or http_stat["statcode"] == 504
    or http_stat["statcode"] == 429 then
    io.stdout:write("Not writing WARC record.\n")
    io.stdout:flush()
    return false
  end
  if string.find(url["url"], "/_reservice_/") then
    local data = read_file(http_stat["local_file"])
    if string.match(data, '"message"%s*:%s*"network timeout at') then
      write_message("Network timeout.\n")
      retry_url = true
      return false
    end
  end
  return true
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]

  if abortgrab then
    abort_item(true)
    submit_discovered()
    return wget.actions.ABORT
    --return wget.actions.EXIT
  end

  set_new_item(url["url"])
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
  io.stdout:flush()

  if exitgrab then
    return wget.actions.EXIT
  end

  if status_code >= 300 and status_code <= 399 then
    local newloc = urlparse.absolute(url["url"], http_stat["newloc"])
    if downloaded[newloc] or addedtolist[newloc]
      or not allowed(newloc, url["url"]) then
      tries = 0
      return wget.actions.EXIT
    end
  end
  
  if status_code >= 200 and status_code <= 399 then
    downloaded[url["url"]] = true
  end

  if (item_type == "kid" or string.match(url["url"], "^https?://[^/]*yahoo%.com/"))
    and status_code == 404 then
    write_message("Possible bad 404 found.\n")
    os.execute("sleep 200")
    abort_item()
  end

  if status_code == 0
    or (status_code > 400 and status_code ~= 404)
    or (
      string.match(url["url"], "^https://[^/]*answers%.yahoo%.com/question/index%?qid=")
      and status_code ~= 200 and status_code ~= 404
    )
    or retry_url then
    retry_url = false
    io.stdout:write("Server returned " .. http_stat.statcode .. " (" .. err .. "). Sleeping.\n")
    io.stdout:flush()
    local maxtries = 10
    if status_code == 403 then
      maxtries = 2
    end
    if tries >= maxtries then
      io.stdout:write("I give up...\n")
      io.stdout:flush()
      tries = 0
      if string.match(url["url"], "^https?://s%.yimg%.com/") and status_code == 403 then
        return wget.actions.EXIT
      end
      if not allowed(url["url"], nil)
        and not string.find(url["url"], "/_reservice_/") then
        return wget.actions.EXIT
      end
      abort_item(true)
      return wget.actions.ABORT
    else
      os.execute("sleep " .. math.floor(math.pow(2, tries)))
      tries = tries + 1
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end

wget.callbacks.finish = function(start_time, end_time, wall_time, numurls, total_downloaded_bytes, total_download_time)
  local file = io.open(item_dir .. '/' .. warc_file_base .. '_bad-items.txt', 'w')
  for url, _ in pairs(bad_items) do
    file:write(url .. "\n")
  end
  file:close()
  submit_discovered()
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab then
    abort_item()
    submit_discovered()
    return wget.exits.IO_FAIL
  end
  return exit_status
end

