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
- name query -> name_full matches "%text%"
- content_type_tree: matches only, value must include %...% (never use eq/neq)
- content_type_tree mapping (matches with %...%): PDF=%public.pdf%, Images=%public.image%, Video=%public.movie%, Docs=%org.openxmlformats.wordprocessingml.document%
- extension: use extension eq "pdf" (no dot, lowercase)
- dates: YYYY-MM-DD only
- relative dates -> date
- size: 1KB=1024, 1MB=1048576, 1GB=1073741824
- downloaded -> downloaded_date
- if scopes has Downloads + time range -> downloaded_date
- modified -> modification_date
- created -> creation_date
</rules>

<keys>
{property_info}
</keys>
