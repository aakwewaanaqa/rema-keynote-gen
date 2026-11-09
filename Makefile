SWIFT_APP := bin/ui/swift_app

run.ui:
	$(SWIFT_APP)/package_app.sh
	open $(SWIFT_APP)/AdvancedBibleQueryApp.app

do.test.all:
	cd $(SWIFT_APP) && swift test

# 會打真的外部聖經網站（BibleGateway、信望愛、holybible.or.kr）
do.test.network:
	cd $(SWIFT_APP) && REMA_NETWORK_TESTS=1 swift test
