{{- define "generic.name" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "generic.labels" -}}
app.kubernetes.io/name: generic
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "generic.fullname" -}}
{{- printf "%s-generic" (include "generic.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
