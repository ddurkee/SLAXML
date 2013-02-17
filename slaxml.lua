--[=====================================================================[
v0.4 Copyright © 2013 Gavin Kistner <!@phrogz.net>; MIT Licensed
See http://github.com/Phrogz/SLAXML for details.
--]=====================================================================]
SLAXML = {
	VERSION = "0.4",
	_call = {
		pi = function(target,content)
			print(string.format("<?%s %s?>",target,content))
		end,
		comment = function(content)
			print(string.format("<!-- %s -->",content))
		end,
		startElement = function(name,nsURI)
			print(string.format("<%s%s>",name,nsURI and (" ("..nsURI..")") or ""))
		end,
		attribute = function(name,value,nsURI)
			print(string.format("  %s=%q%s",name,value,nsURI and (" ("..nsURI..")") or ""))
		end,
		text = function(text)
			print(string.format("  text: %q",text))
		end,
		closeElement = function(name)
			print(string.format("</%s>",name))
		end,
		namespace = function(nsURI) -- applies a default namespace to the current element
			print(string.format("  (xmlns=%s)",nsURI))
		end,
	}
}

function SLAXML:parser(callbacks)
	return { _call=callbacks or self._call, parse=SLAXML.parse }
end

function SLAXML:parse(xml,options)
	if not options then options = { stripWhitespace=false } end

	-- Cache references for maximum speed
	local find, sub, gsub, char, push, pop = string.find, string.sub, string.gsub, string.char, table.insert, table.remove
	local first, last, match1, match2, match3, pos2, nsURI
	local pos = 1
	local state = "text"
	local textStart = 1
	local currentElement
	local nsStack = {}

	local entityMap  = { ["lt"]="<", ["gt"]=">", ["amp"]="&", ["quot"]='"', ["apos"]="'" }
	local entitySwap = function(orig,n,s) return entityMap[s] or n=="#" and char(s) or orig end
	local function unescape(str) return gsub( str, '(&(#?)([%d%a]+);)', entitySwap ) end

	local function finishText()
		if first>textStart and self._call.text then
			local text = sub(xml,textStart,first-1)
			if options.stripWhitespace then
				text = gsub(text,'^%s+','')
				text = gsub(text,'%s+$','')
				if #text==0 then text=nil end
			end
			if text then self._call.text(unescape(text)) end
		end
	end

	local function findPI()
		first, last, match1, match2 = find( xml, '^<%?([:%a_][:%w_.-]*) ?(.-)%?>', pos )
		if first then
			finishText()
			if self._call.pi then self._call.pi(match1,match2) end
			pos = last+1
			textStart = pos
			return true
		end
	end

	local function findComment()
		first, last, match1 = find( xml, '^<!%-%-(.-)%-%->', pos )
		if first then
			finishText()
			if self._call.comment then self._call.comment(match1) end
			pos = last+1
			textStart = pos
			return true
		end
	end

	local function nsForPrefix(prefix)
		for i=#nsStack,1,-1 do if nsStack[i][prefix] then return nsStack[i][prefix] end end
		error(("Cannot find namespace for prefix %s"):format(prefix))
	end

	local function startElement()
		first, last, match1 = find( xml, '^<([%a_][%w_.-]*)', pos )
		if first then
			nsURI = nil
			finishText()
			pos = last+1
			first,last,match2 = find(xml, '^:([%a_][%w_.-]*)', pos )
			if first then
				nsURI = nsForPrefix(match1)
				currentElement = match2
				match1 = match2
				pos = last+1
			else
				currentElement = match1
				for i=#nsStack,1,-1 do if nsStack[i]['!'] then nsURI = nsStack[i]['!']; break end end
			end
			if self._call.startElement then self._call.startElement(match1,nsURI) end
			push(nsStack,{})
			return true
		end
	end

	local function findAttribute()
		first, last, match1 = find( xml, '^%s+([:%a_][:%w_.-]*)%s*=%s*', pos )
		if first then
			pos2 = last+1
			first, last, match2 = find( xml, '^"([^<"]+)"', pos2 ) -- FIXME: disallow non-entity ampersands
			if first then
				pos = last+1
				match2 = unescape(match2)
			else
				first, last, match2 = find( xml, "^'([^<']+)'", pos2 ) -- FIXME: disallow non-entity ampersands
				if first then
					pos = last+1
					match2 = unescape(match2)
				end
			end
		end
		if match1 and match2 then
			nsURI = nil
			local prefix,name = string.match(match1,'^([^:]+):([^:]+)$')
			if prefix then
				if prefix=='xmlns' then
					nsStack[#nsStack][name] = match2
				else
					nsURI = nsForPrefix(prefix)
					match1 = name
				end
			else
				if match1=='xmlns' then
					nsStack[#nsStack]['!'] = match2
					if self._call.namespace then self._call.namespace(match2) end
				end
			end
			if self._call.attribute then self._call.attribute(match1,match2,nsURI) end
			return true
		end
	end

	local function findCDATA()
		first, last, match1 = find( xml, '^<!%[CDATA%[(.-)%]%]>', pos )
		if first then
			finishText()
			if self._call.text then self._call.text(match1) end
			pos = last+1
			textStart = pos
			return true
		end
	end

	local function closeElement()
		first, last, match1 = find( xml, '^%s*(/?)>', pos )
		if first then
			state = "text"
			pos = last+1
			textStart = pos
			if match1=="/" then
				pop(nsStack)
				if self._call.closeElement then self._call.closeElement(currentElement) end
			end
			return true
		end
	end

	local function findElementClose()
		first, last, match1 = find( xml, '^</([:%a_][:%w_.-]*)%s*>', pos )
		if first then
			finishText()
			if self._call.closeElement then self._call.closeElement(match1) end
			pos = last+1
			textStart = pos
			pop(nsStack)
			return true
		end
	end

	while pos<#xml do
		if state=="text" then
			if not (findPI() or findComment() or findCDATA() or findElementClose()) then		
				if startElement() then
					state = "attributes"
				else
					-- TODO: scan up until the next < for speed
					pos = pos + 1
				end
			end
		elseif state=="attributes" then
			if not findAttribute() then
				if not closeElement() then
					error("Was in an element and couldn't find attributes or the close.")
				end
			end
		end
	end
end