# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 Anil Belur
ARG BUILD_FROM
FROM ${BUILD_FROM}

RUN apk add --no-cache git curl jq bash

COPY rootfs /
RUN chmod a+x /app/gitops_backup.sh /etc/services.d/gitops/run

LABEL \
  io.hass.type="addon" \
  org.opencontainers.image.source="https://github.com/askb/ha-gitops-backup" \
  org.opencontainers.image.licenses="Apache-2.0"
