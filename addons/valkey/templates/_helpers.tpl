{{/* vim: set filetype=mustache: */}}

{{- define "valkey.name" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "valkey.labels" -}}
app.kubernetes.io/name: valkey
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "valkey.tlsSecretName" -}}
{{- printf "%s-tls" (include "valkey.name" .) -}}
{{- end -}}
