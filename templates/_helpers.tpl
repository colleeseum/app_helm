{{/* ===== Insight Engine helpers (no common dependency) ===== */}}

{{- define "insightengine.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "insightengine.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" $name .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "insightengine.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
{{- end -}}

{{- define "insightengine.labels.selector" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "insightengine.labels.standard" -}}
{{ include "insightengine.labels" . }}
{{- end -}}

{{- define "insightengine.podScheduling" -}}
{{- $vals := .Values -}}
{{- $hasNodeSelector := and $vals (hasKey $vals "nodeSelector") (not (empty $vals.nodeSelector)) -}}
{{- $hasTolerations := and $vals (hasKey $vals "tolerations") (not (empty $vals.tolerations)) -}}
{{- if or $hasNodeSelector $hasTolerations }}
{{- if $hasNodeSelector }}
nodeSelector:
{{ toYaml $vals.nodeSelector | indent 2 }}
{{- end }}
{{- if $hasTolerations }}
tolerations:
{{ toYaml $vals.tolerations | indent 2 }}
{{- end }}
{{- end -}}
{{- end -}}

{{- define "insightengine.ensureSecretExists" -}}
{{- $ctx := .context -}}
{{- $name := .name -}}
{{- $ns := default $ctx.Release.Namespace .namespace -}}
{{- $secret := lookup "v1" "Secret" $ns $name -}}
{{- if not $secret }}
{{- fail (printf "Secret %s/%s not found. Please create it or choose an existing secret." $ns $name) -}}
{{- end -}}
{{- end -}}

{{- define "insightengine.ingressResource" -}}
{{- $ctx := .context -}}
{{- $name := required "ingress name is required" .name -}}
{{- $rules := required "ingress rules are required" .rules -}}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ $name }}
  namespace: {{ $ctx.Release.Namespace }}
  labels:
{{ include "insightengine.labels.standard" $ctx | indent 4 }}
  {{- with .extraLabels }}
{{ toYaml . | indent 4 }}
  {{- end }}
  {{- with .annotations }}
  annotations:
{{ toYaml . | indent 4 }}
  {{- end }}
spec:
  {{- with .className }}
  ingressClassName: {{ . | quote }}
  {{- end }}
  rules:
{{ toYaml $rules | indent 4 }}
  {{- with .tls }}
  tls:
{{ toYaml . | indent 4 }}
  {{- end }}
{{- end -}}

{{- define "insightengine.acmeSolvers" -}}
{{- $ctx := . -}}
{{- $values := .Values -}}
{{- $solvers := default (list) $values.certIssuer.acme.solvers -}}
{{- if not (gt (len $solvers) 0) }}
  {{- $solvers = list }}
  {{- if and $values.gateway $values.gateway.enabled }}
    {{- $parentRefs := list }}
    {{- $create := true -}}
    {{- if hasKey $values.gateway "createGateway" }}
      {{- $create = $values.gateway.createGateway -}}
    {{- end }}
    {{- if $create }}
      {{- $gatewayName := default (printf "%s-gateway" (include "insightengine.fullname" $ctx)) $values.gateway.name }}
      {{- $parentRefs = list (dict "name" $gatewayName "namespace" $ctx.Release.Namespace) }}
    {{- else if $values.gateway.parentRefs }}
      {{- $parentRefs = $values.gateway.parentRefs }}
    {{- end }}
    {{- if gt (len $parentRefs) 0 }}
      {{- $gatewaySolver := dict "http01" (dict "gatewayHTTPRoute" (dict "parentRefs" $parentRefs )) }}
      {{- $solvers = append $solvers $gatewaySolver }}
    {{- end }}
  {{- end }}
  {{- if and $values.ingress $values.ingress.enabled }}
    {{- $ingressBlock := dict }}
    {{- if $values.ingress.className }}
      {{- $_ := set $ingressBlock "class" $values.ingress.className -}}
    {{- end }}
    {{- if not (hasKey $ingressBlock "class") }}
      {{- $_ := set $ingressBlock "class" "nginx" -}}
    {{- end }}
    {{- $ingressSolver := dict "http01" (dict "ingress" $ingressBlock ) }}
    {{- $solvers = append $solvers $ingressSolver }}
  {{- end }}
{{- end }}
{{- if not (gt (len $solvers) 0) }}
  {{- fail "certIssuer.acme.solvers is empty. Provide certIssuer.acme.solvers or enable ingress/gateway to auto-configure HTTP-01 solvers." -}}
{{- end }}
{{- toYaml $solvers -}}
{{- end -}}

{{- define "insightengine.imagePullSecret" -}}
{{- if and (hasKey .Values "image") .Values.image.username .Values.image.password -}}
{{- printf "{\"auths\": {\"%s\": {\"auth\": \"%s\"}}}" .Values.image.registry (printf "%s:%s" .Values.image.username .Values.image.password | b64enc) | b64enc -}}
{{- else -}}
{{- "" -}}
{{- end -}}
{{- end -}}

{{/* Returns the service port with fallbacks:
      1) .Values.service.port
      2) .Values.global.insightEngine.port
      3) .Values.global.insightEngine.service.port (legacy)
      4) 3000
*/}}
{{- define "insightengine.servicePort" -}}
{{- $service := .Values.service | default (dict) -}}
{{- $global := .Values.global | default (dict) -}}
{{- $ie := index $global "insightEngine" | default (dict) -}}
{{- $legacySvc := index $ie "service" | default (dict) -}}
{{- $svcPort := default 3000 (coalesce (index $service "port") (index $ie "port") (index $legacySvc "port")) -}}
{{- printf "%v" $svcPort -}}
{{- end -}}

{{- define "certIssuer.kind" -}}
{{- if .Values.certIssuer.clusterScoped }}ClusterIssuer{{ else }}Issuer{{ end }}
{{- end }}

{{- define "certIssuer.secretName.ie" -}}
{{- default (printf "insight-engine-%s-tls" .Release.Name) .Values.ingress.tls.secretName -}}
{{- end -}}

{{- define "certIssuer.name.ie" -}}
{{- default (printf "%s-certissuer-ie" .Release.Name) .Values.certIssuer.name -}}
{{- end }}

{{- define "certIssuer.privateKeySecretName" -}}
{{- default (printf "%s-account-key" (include "certIssuer.name.ie" .)) .Values.certIssuer.acme.privateKeySecretName -}}
{{- end -}}

{{- define "certIssuer.labels" -}}
app.kubernetes.io/name: {{ include "certIssuer.name.ie" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
