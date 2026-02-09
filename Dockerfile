ARG BASE_IMAGE
ARG BUILD_IMAGE

FROM ${BUILD_IMAGE} as solidity-build
WORKDIR /home/node
ADD ./samples/solidity/package*.json ./
RUN npm install
ADD ./samples/solidity .
RUN npx hardhat compile

FROM ${BUILD_IMAGE} AS build
WORKDIR /root
ADD package*.json ./
RUN npm install
ADD . .
RUN npm run build && npm prune --omit dev

FROM alpine:3.21 AS sbom
WORKDIR /
ADD . /SBOM
RUN apk add --no-cache curl
RUN curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin v0.68.2
RUN trivy fs \
  --db-repository public.ecr.aws/aquasecurity/trivy-db \
  --java-db-repository public.ecr.aws/aquasecurity/trivy-java-db \
  --scanners vuln,license \
  --vuln-severity-source nvd,ubuntu,amazon,govulndb,ghsa,nodejs-security-wg,azure,redhat,k8s,debian \
  --sbom-sources oci,rekor \
  --format spdx-json \
  --output /sbom.spdx.json \
  /SBOM

FROM $BASE_IMAGE
# We also need to keep copying it to the old location to maintain compatibility with the FireFly CLI
COPY --from=solidity-build --chown=1001:0 /home/node/artifacts/contracts/ERC1155MixedFungible.sol/ERC1155MixedFungible.json /root/contracts/
WORKDIR /app
ADD package*.json ./
COPY --from=solidity-build /home/node/contracts contracts/source
COPY --from=solidity-build /home/node/artifacts/contracts/ERC1155MixedFungible.sol contracts
COPY --from=builder /root/node_modules/ /app/node_modules/
COPY --from=builder /root/package.json /app/package.json
COPY --from=builder /root/package-lock.json /app/package-lock.json
COPY --from=build /root/dist dist
COPY --from=build /root/.env /app/.env
RUN chgrp -R 0 /app/ \
    && chmod -R g+rwX /app/
COPY --from=sbom /sbom.spdx.json /sbom.spdx.json
USER 1001
EXPOSE 3000
CMD ["node", "dist/src/main"]
