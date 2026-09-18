ARG UBUNTU_VERSION=24.04

FROM ubuntu:${UBUNTU_VERSION} AS toolchain

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

FROM toolchain AS build

ENV PATH=/opt/gnucobol/bin:${PATH} \
    LD_LIBRARY_PATH=/opt/gnucobol/lib

WORKDIR /workspace
COPY copybooks/ copybooks/
COPY programs/ programs/
COPY scripts/ scripts/
COPY data/ data/
COPY tests/ tests/

RUN scripts/run-tests.sh
RUN cobc -x -std=ibm -fixed -I copybooks \
        -o build/bin/CSTSOAP programs/adapter/CSTSOAP.cbl

FROM ubuntu:${UBUNTU_VERSION} AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends libgmp10 apache2 curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10002 custcore \
    && useradd --system --uid 10002 --gid custcore --home-dir /nonexistent --no-create-home --shell /usr/sbin/nologin custcore \
    && mkdir -p /var/lib/custcore \
    && chown custcore:custcore /var/lib/custcore

COPY --from=toolchain /opt/gnucobol/lib/ /opt/gnucobol/lib/
COPY --from=build /workspace/build/bin/ /opt/custcore/bin/
COPY --from=build /workspace/data/ /opt/custcore/baseline/
COPY www/ /opt/custcore/www/
COPY runtime/httpd.conf /opt/custcore/httpd.conf
COPY runtime/entrypoint.sh /opt/custcore/entrypoint.sh

ENV LD_LIBRARY_PATH=/opt/gnucobol/lib \
    COB_LIBRARY_PATH=/opt/custcore/bin \
    CUSTCORE_DATA_DIR=/var/lib/custcore \
    SERVICE_PORT=8081

USER 10002:10002
EXPOSE 8081

HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -fsS -o /dev/null -H 'SOAPAction: GetCustomer' -H 'Content-Type: text/xml' \
        --data '<Envelope><Body><GetCustomer><customerId>0000000001</customerId></GetCustomer></Body></Envelope>' \
        "http://127.0.0.1:${SERVICE_PORT}/customer-service"

ENTRYPOINT ["/opt/custcore/entrypoint.sh"]
