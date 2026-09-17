ARG UBUNTU_VERSION=24.04

FROM --platform=linux/amd64 ubuntu:${UBUNTU_VERSION} AS toolchain

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential libgmp-dev xz-utils ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ADD --checksum=sha256:3bb48af46ced4779facf41fdc2ee60e4ccb86eaa99d010b36685315df39c2ee2 \
    https://ftp.gnu.org/gnu/gnucobol/gnucobol-3.2.tar.xz /tmp/gnucobol.tar.xz
RUN mkdir /tmp/gnucobol \
    && tar xJf /tmp/gnucobol.tar.xz -C /tmp/gnucobol --strip-components=1 \
    && cd /tmp/gnucobol \
    && ./configure --prefix=/opt/gnucobol --without-db --without-curses --without-xml2 --without-json --disable-nls \
    && make -j"$(nproc)" \
    && make install \
    && rm -rf /tmp/gnucobol /tmp/gnucobol.tar.xz

ADD --checksum=sha256:d01fa65721639040755ab155291d1f6327bd429e4f503748abe0f3b3a04fa853 \
    https://public.dhe.ibm.com/ibmdl/export/pub/software/websphere/messaging/mqdev/redist/9.4.5.1-IBM-MQC-Redist-LinuxX64.tar.gz \
    /tmp/mqclient.tar.gz
RUN mkdir -p /opt/mqm \
    && tar xzf /tmp/mqclient.tar.gz -C /opt/mqm \
    && rm -rf /tmp/mqclient.tar.gz /opt/mqm/java

FROM toolchain AS build

ENV PATH=/opt/gnucobol/bin:${PATH} \
    LD_LIBRARY_PATH=/opt/gnucobol/lib:/opt/mqm/lib64

WORKDIR /workspace
COPY copybooks/ copybooks/
COPY programs/ programs/
COPY scripts/ scripts/
COPY data/ data/
COPY tests/ tests/

RUN scripts/run-tests.sh
RUN for program in BKMQLSN BKMQREQ; do \
        cobc -x -std=ibm -fixed -fnotrunc -fstatic-call \
            -I copybooks -I /opt/mqm/inc/cobcpy64 \
            -o "build/bin/${program}" "programs/adapter/${program}.cbl" \
            -L/opt/mqm/lib64 -lmqicb || exit 1; \
    done

FROM --platform=linux/amd64 ubuntu:${UBUNTU_VERSION} AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends libgmp10 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 bankcore \
    && useradd --system --uid 10001 --gid bankcore --home-dir /nonexistent --no-create-home --shell /usr/sbin/nologin bankcore \
    && mkdir -p /var/lib/bankcore \
    && chown bankcore:bankcore /var/lib/bankcore

COPY --from=toolchain /opt/gnucobol/lib/ /opt/gnucobol/lib/
COPY --from=toolchain /opt/mqm/ /opt/mqm/
COPY --from=build /workspace/build/bin/ /opt/bankcore/bin/
COPY --from=build /workspace/data/ /opt/bankcore/baseline/
COPY runtime/entrypoint.sh /opt/bankcore/entrypoint.sh

ENV LD_LIBRARY_PATH=/opt/gnucobol/lib:/opt/mqm/lib64 \
    COB_LIBRARY_PATH=/opt/bankcore/bin \
    BANKCORE_DATA_DIR=/var/lib/bankcore \
    MQ_OVERRIDE_DATA_PATH=/tmp/mqclient

USER 10001:10001

ENTRYPOINT ["/opt/bankcore/entrypoint.sh"]
