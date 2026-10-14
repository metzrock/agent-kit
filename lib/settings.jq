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
{document:.,entries:$journal}
| if $mode=="remove" then
    reduce ($journal[]|select(.module==$module)) as $e (.; .document |= undo($e))
    | reduce ($journal[]|select(.module==$module)) as $e (.; .document |= clean($e))
    | .entries |= map(select(.module!=$module))
  else
    reduce ($patch|leafpaths) as $p (.;
      ($patch|getpath($p)) as $v
      | .document as $doc
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
                (reduce $v[] as $x (($before // []); if index($x)!=null then . else .+[$x] end)) as $after
                | .document |= setpath($p;$after)
                | .entries += [{module:$module,path:$p,parents:$parents,array:true,present:$present,added:($v-($before // []))}]
              else .document |= setpath($p;$v)
                | .entries += [{module:$module,path:$p,parents:$parents,array:false,present:$present,before:$before,value:$v}] end
          end
        else
          parents(.document;$p) as $parents
          | (.document|getpath($p)) as $before
          | (.document|any(paths; .==$p)) as $present
          | if ($v|type)=="array" then
              if $before!=null and ($before|type)!="array" then error("settings array conflicts with user value") else
              .document |= setpath($p;(reduce $v[] as $x (($before // []); if index($x)!=null then . else .+[$x] end)))
              | .entries += [{module:$module,path:$p,parents:$parents,array:true,present:$present,added:($v-($before // []))}] end
            elif $present then .
            else .document |= setpath($p;$v)
              | .entries += [{module:$module,path:$p,parents:$parents,array:false,present:false,before:null,value:$v}] end
        end)
  end
