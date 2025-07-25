SRC_NAME = iperf-3.18
SRC_URL = https://downloads.es.net/pub/iperf/iperf-3.18.tar.gz
THISDIR = $(shell pwd)

all: download_test extract_test config_test
	$(MAKE) -j$(HOST_NCPU) -C $(SRC_NAME)

download_test:
	( if [ ! -f $(SRC_NAME).tar.gz ]; then \
		wget -t5 --timeout=20 --no-check-certificate -O $(SRC_NAME).tar.gz $(SRC_URL); \
	fi )

extract_test:
	( if [ ! -d $(SRC_NAME) ]; then \
		tar -xf $(SRC_NAME).tar.gz; \
	fi )

config_test:
	( if [ -f ./config_done ]; then \
		echo "the same configuration"; \
	else \
		make configure && touch config_done; \
	fi )

configure:
	( cd $(SRC_NAME) ; ./bootstrap.sh && \
	./configure \
		LDFLAGS="$(LDFLAGS) -latomic -lpthread" \
		--prefix=/usr \
		--disable-profiling \
		--without-openssl \
		--disable-shared \
		--enable-static \
		--host=$(HOST_TARGET) \
		--build=$(HOST_BUILD) ; \
	)

clean:
	if [ -f $(SRC_NAME)/Makefile ] ; then \
		$(MAKE) -C $(SRC_NAME) distclean ; \
	fi ; \
	rm -f config_done

romfs:
	$(STRIP) $(THISDIR)/$(SRC_NAME)/src/iperf3
	$(ROMFSINST) -p +x $(THISDIR)/$(SRC_NAME)/src/iperf3 /usr/bin/iperf3
	cp -fP $(CONFIG_CROSS_COMPILER_ROOT)/mipsel-linux-uclibc/sysroot/lib/libatomic.so* $(ROMFSDIR)/lib

