# Normalize only the executable, not arbitrary shell fragments.
def executable:
  sub("^ +"; "")
  | if startswith("\"") then split("\"")[1]
    elif startswith("'") then split("'")[1]
    else split(" ")[0] end
  | gsub("[\"']"; "") | gsub("\\$\\{HOME\\}|\\$HOME"; $home)
  | sub("^~(?=/)"; $home);
def commands: [.hooks[]?.command? | strings | executable];
def same_script($a;$b):
  $a==$b or (($a|contains("/")|not) and $a==($b|split("/")[-1]))
  or (($b|contains("/")|not) and $b==($a|split("/")[-1]));
def skipped_command: executable as $script | any($skipped[]; same_script(.;$script));
def filtered_patch:
  if (.statusLine.command? | type)=="string" and (.statusLine.command|skipped_command) then del(.statusLine) else . end
  | if (.hooks?|type)=="object" then .hooks |= map_values(
      if type=="array" then map(
        if (.hooks?|type)=="array" then
          .hooks |= map(select(if (.command?|type)=="string" then (.command|skipped_command|not) else true end))
          | select(.hooks|length>0)
        else . end)
      else . end)
    else . end;
def additions($before;$v;$p):
  if $p[0]=="hooks" then
    [$before[] | commands[]] as $existing
    | [$v[] | if (.hooks?|type)=="array" then
        .hooks |= map(. as $hook | select(
          if ($hook.command?|type)=="string" then
            any($existing[]; same_script(.;($hook.command|executable)))|not
          else true end))
        | select(.hooks|length>0)
      else . as $x | select($before|index($x)==null) end]
  else [$v[] | . as $x | select($before|index($x)==null)] end;
# Ownership tags live in state.json, never in Claude's settings schema.
def leaves($p): if type=="object" then to_entries[] | .key as $k | .value | leaves($p+[$k]) else $p end;
def leafpaths: leaves([]);
def remove_added($added): reduce $added[] as $item (.; index($item) as $i | if $i==null then . else .[0:$i]+.[($i+1):] end);
def parents($doc;$p): [range(1; $p|length) as $n | $p[0:$n] | select(. as $q | ($doc|any(paths; .==$q)|not))];
def clean($e): reduce (($e.parents // [])|reverse[]) as $p (.; if getpath($p)=={} then delpaths([$p]) else . end);
def undo($e):
  if $e.array then
    if (getpath($e.path)|type)=="array" then
      setpath($e.path; (getpath($e.path)|remove_added($e.added)))
      | if ($e.present|not) and getpath($e.path)==[] then delpaths([$e.path]) | clean($e) else . end
    else . end
  elif getpath($e.path)==$e.value then
    if $e.present then setpath($e.path;$e.before)
    else delpaths([$e.path]) | clean($e) end
  else . end;
($patch|filtered_patch) as $filtered
| {document:.,entries:$journal}
| if $mode=="remove" then
    reduce ($journal[]|select(.module==$module)) as $e (.; .document |= undo($e))
    | reduce ($journal[]|select(.module==$module)) as $e (.; .document |= clean($e))
    | .entries |= map(select(.module!=$module))
  else
    # Remove only kit-owned statusLine leaves when its executable was skipped.
    if ($patch|has("statusLine")) and ($filtered|has("statusLine")|not) then
      reduce (.entries[]|select(.module==$module and .path[0]=="statusLine")) as $e (.; .document |= undo($e))
      | reduce (.entries[]|select(.module==$module and .path[0]=="statusLine")) as $e (.; .document |= clean($e))
      | .entries |= map(select(.module!=$module or .path[0]!="statusLine"))
    else . end
    | reduce ($filtered|leafpaths) as $p (.;
      ($filtered|getpath($p)) as $v
      | if $p[0]=="statusLine" and (.document|has("statusLine")) and
          ([.entries[]|select(.path[0]=="statusLine")]|length)==0 then . else
      .document as $doc
      | if any(range(1; $p|length); . as $n | ($doc|getpath($p[0:$n])) as $parent | $parent!=null and ($parent|type)!="object") then error("settings parent conflicts with user value") else . end
      | ([.entries[]|select(.module==$module and .path==$p)][0]) as $old
      | if $old != null then
          # Preserve explicit user edits to scalar settings on update.
          if ($old.array|not) and (.document|getpath($p))!=$old.value then .
          else .document |= undo($old)
            | .entries |= map(select(.module!=$module or .path!=$p))
            | . as $s
            | ((parents(.document;$p) + ($old.parents // []))|unique) as $parents
            | ($s.document|getpath($p)) as $before
            | ($s.document|any(paths; .==$p)) as $present
            | if ($v|type)=="array" then
                (($before // []) + additions(($before // []);$v;$p)) as $after
                | .document |= setpath($p;$after)
                | .entries += [{module:$module,path:$p,parents:$parents,array:true,present:$present,added:additions(($before // []);$v;$p)}]
              else .document |= setpath($p;$v)
                | .entries += [{module:$module,path:$p,parents:$parents,array:false,present:$present,before:$before,value:$v}] end
          end
        else
          parents(.document;$p) as $parents
          | (.document|getpath($p)) as $before
          | (.document|any(paths; .==$p)) as $present
          | if ($v|type)=="array" then
              if $before!=null and ($before|type)!="array" then error("settings array conflicts with user value") else
              .document |= setpath($p;(($before // []) + additions(($before // []);$v;$p)))
              | .entries += [{module:$module,path:$p,parents:$parents,array:true,present:$present,added:additions(($before // []);$v;$p)}] end
            elif $present then .
            else .document |= setpath($p;$v)
              | .entries += [{module:$module,path:$p,parents:$parents,array:false,present:false,before:null,value:$v}] end
        end end)
  end
