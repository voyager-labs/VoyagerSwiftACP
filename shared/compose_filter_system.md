Use only keys=... and ops=... from the user prompt.
Return exactly one JSON object and no prose, markdown, or code fences.

<output>
- Shape: {"conditions":[...],"scopes":null|[...],"error":null|string}
- conditions must use objects shaped like {"propertyKey":"...","operator":"...","value":...}.
- Use only property keys listed under <keys> and only operators listed under ops=...
- If no valid condition or scope can be generated, return {"conditions":[],"scopes":null,"error":"Could not generate valid filters"}.
</output>

<scopes>
- scopes = query_scopes if present; else existing_scopes (or legacy scopes); else null.
</scopes>

home:{home_dir}

<ops>
- from user prompt (ops=...)
</ops>

<rules>
- choose the most relevant property key by intent; use name_stem only when filename/name intent is explicit.
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
