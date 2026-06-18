{{/*
  Loads an addon from either a single-file (files/foo.yaml) or
  directory (files/foo/meta.yaml) layout and returns merged YAML.
  Pass (dict "root" $ "path" $path).
*/}}
{{- define "classes.loadDir" -}}
{{- $root := .root -}}
{{- $path := .path -}}
{{- if hasSuffix "/meta.yaml" $path -}}
{{- $dir := $path | dir -}}
{{- $values := $root.Files.Get $path | fromYaml -}}
{{- if $root.Files.Glob (printf "%s/schema.yaml" $dir) -}}
{{- $_ := set $values "schema" ($root.Files.Get (printf "%s/schema.yaml" $dir) | fromYaml) -}}
{{- end -}}
{{- if $root.Files.Glob (printf "%s/plans.yaml" $dir) -}}
{{- $_ := set $values "plans" ($root.Files.Get (printf "%s/plans.yaml" $dir) | fromYamlArray) -}}
{{- end -}}
{{- toYaml $values -}}
{{- else -}}
{{- $root.Files.Get $path -}}
{{- end -}}
{{- end -}}

{{/*
  Iterates over all addons (single-file + directory) and includes
  a named template for each. Pass (dict "root" $ "body" "templateName").
  The body receives (dict "values" $values "addonName" $addonName).
*/}}
{{- define "classes.iterate" -}}
{{- $root := .root -}}
{{- $body := .body -}}

{{- range $path, $_ := $root.Files.Glob "files/*.yaml" -}}
{{- $values := $root.Files.Get $path | fromYaml -}}
{{- $addonName := $path | base | trimSuffix ".yaml" -}}
{{- include $body (dict "values" $values "addonName" $addonName) -}}
{{- end -}}

{{- range $path, $_ := $root.Files.Glob "files/*/meta.yaml" -}}
{{- $values := (include "classes.loadDir" (dict "root" $root "path" $path)) | fromYaml -}}
{{- $addonName := $path | dir | base -}}
{{- include $body (dict "values" $values "addonName" $addonName) -}}
{{- end -}}
{{- end -}}
