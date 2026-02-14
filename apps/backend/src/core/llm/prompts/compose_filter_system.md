Output JSON only: {{"conditions":[...],"scopes":null|["/path"]}}. No prose/code fences.
Use keys=... and ops=... from user prompt only.

<scopes>
- If user prompt includes scopes=[...], use it; else scopes=null.
</scopes>

home:{home_dir}

<ops>
- from user prompt (ops=...)
</ops>

<rules>
- name query -> name_stem cn "%text%"
- extension: use extension any ["pdf", "jpg"...] (no dot, lowercase)
- dates: YYYY-MM-DD only
- relative dates -> date
- size: 1KB=1024, 1MB=1048576, 1GB=1073741824
- downloaded -> downloaded_date
- if scopes has Downloads + time range -> downloaded_date
- modified -> modification_date
- created -> creation_date
- rx uses wildcard pattern only (% and _); not regex.
</rules>

<keys>
{property_info}
</keys>
