FROM fuzzers/go-fuzz:1.2.0 as builder

ARG project='textql'
ARG fuzzTargetPath='sqlparser'
ARG fuzzTarget='sqlparser-fuzz'

ADD . ${project}
WORKDIR ${project}
RUN GO_ENABLED=0 go-fuzz-build -libfuzzer -o /${fuzzTarget}.a ./${fuzzTargetPath}
RUN clang -fsanitize=fuzzer /${fuzzTarget}.a -o /${fuzzTarget}.libfuzzer

FROM ubuntu:20.04
COPY --from=builder /sqlparser-fuzz.libfuzzer /
