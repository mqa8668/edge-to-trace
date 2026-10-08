FROM golang:1.27@sha256:162be5298a40ed317005c8339c6de4d10d3eef336d66dc8e9259b03ab9d3a6d2 AS build
WORKDIR /src
COPY go.mod ./
COPY *.go ./

FROM build AS test
RUN go vet ./... && go test ./...

FROM build AS compile
ENV CGO_ENABLED=0
RUN go build -trimpath -ldflags="-s -w" -o /out/alert-sink .

FROM gcr.io/distroless/static-debian12:nonroot@sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab
COPY --from=compile /out/alert-sink /alert-sink
USER 65532:65532
EXPOSE 9095
HEALTHCHECK --interval=10s --timeout=3s --start-period=3s --retries=3 CMD ["/alert-sink", "-healthcheck"]
ENTRYPOINT ["/alert-sink"]
