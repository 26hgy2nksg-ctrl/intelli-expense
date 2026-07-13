SHELL := /bin/zsh
.DEFAULT_GOAL := help

-include Makefile.local

PROJECT := IntelliExpense.xcodeproj
SCHEME := IntelliExpense
APP_TARGET := IntelliExpense
SANDBOX_SCHEME := IntelliExpenseSandbox
SANDBOX_APP_TARGET := IntelliExpenseSandbox
MAC_SCHEME := IntelliExpenseMac
SIM_DEST ?= platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5
MAC_DEST ?= platform=macOS
DEVICE_ID ?=
DERIVED_DATA ?= build/DerivedData
BETA_DERIVED_DATA ?= build/DerivedData-xcode27
SANDBOX_DERIVED_DATA ?= build/DerivedData-sandbox
XCODE_BETA_DIR ?= /Volumes/External-2TB/Applications/Xcode-27-beta.app
XCODE_BETA_DEVELOPER_DIR := $(XCODE_BETA_DIR)/Contents/Developer
TEAM_ID ?=
BUNDLE_ID ?= com.nags.intelliexpense
SANDBOX_BUNDLE_ID ?= com.nags.intelliexpense.sandbox
BUNDLE_RESOURCE_ID ?=
CLOUDKIT_CONTAINER ?= iCloud.com.nags.intelliexpense
ASC_APP_ID ?=
DISTRIBUTION_CERTIFICATE_ID ?=
DEVELOPMENT_CERTIFICATE_ID ?=
DEVELOPMENT_CODE_SIGN_STYLE ?= Automatic
DISTRIBUTION_CODE_SIGN_STYLE ?= Automatic
DEVELOPMENT_SIGNING_IDENTITY ?=
DISTRIBUTION_SIGNING_IDENTITY ?=
DISTRIBUTION_PROFILE_NAME ?=
DEVELOPMENT_PROFILE_NAME ?=
SHARE_DISTRIBUTION_PROFILE_NAME ?=
SHARE_DEVELOPMENT_PROFILE_NAME ?=
CONTROLS_DEVELOPMENT_PROFILE_NAME ?=
CONTROLS_DISTRIBUTION_PROFILE_NAME ?=
MAC_DEVELOPMENT_PROFILE_NAME ?=
PROFILE_NAME ?= $(DISTRIBUTION_PROFILE_NAME)
PROFILE_ID ?=
ASC_DEVICE_ID ?=
TESTFLIGHT_GROUP_ID ?=
ARCHIVE_PATH ?= build/IntelliExpense.xcarchive
EXPORT_PATH ?= build/export
EXPORT_OPTIONS ?= Config/ExportOptions.AppStore.plist
IPA ?= $(EXPORT_PATH)/IntelliExpense.ipa
SANDBOX_UNINSTALL_FIRST ?= 1
DEVICE_SIGNING_SETTINGS = INTELLI_TEAM_ID="$(TEAM_ID)" INTELLI_DEVELOPMENT_CODE_SIGN_STYLE="$(DEVELOPMENT_CODE_SIGN_STYLE)" $(if $(filter Manual,$(DEVELOPMENT_CODE_SIGN_STYLE)),INTELLI_DEVELOPMENT_SIGNING_IDENTITY="$(DEVELOPMENT_SIGNING_IDENTITY)" INTELLI_DEVELOPMENT_PROFILE="$(DEVELOPMENT_PROFILE_NAME)" INTELLI_SHARE_DEVELOPMENT_PROFILE="$(SHARE_DEVELOPMENT_PROFILE_NAME)" INTELLI_CONTROLS_DEVELOPMENT_PROFILE="$(CONTROLS_DEVELOPMENT_PROFILE_NAME)",-allowProvisioningUpdates)
RELEASE_SIGNING_SETTINGS = INTELLI_TEAM_ID="$(TEAM_ID)" INTELLI_DISTRIBUTION_CODE_SIGN_STYLE="$(DISTRIBUTION_CODE_SIGN_STYLE)" $(if $(filter Manual,$(DISTRIBUTION_CODE_SIGN_STYLE)),INTELLI_DISTRIBUTION_SIGNING_IDENTITY="$(DISTRIBUTION_SIGNING_IDENTITY)" INTELLI_DISTRIBUTION_PROFILE="$(DISTRIBUTION_PROFILE_NAME)" INTELLI_SHARE_DISTRIBUTION_PROFILE="$(SHARE_DISTRIBUTION_PROFILE_NAME)" INTELLI_CONTROLS_DISTRIBUTION_PROFILE="$(CONTROLS_DISTRIBUTION_PROFILE_NAME)",-allowProvisioningUpdates)
MAC_SIGNING_SETTINGS = DEVELOPMENT_TEAM="$(TEAM_ID)" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$(DEVELOPMENT_SIGNING_IDENTITY)" PROVISIONING_PROFILE_SPECIFIER="$(MAC_DEVELOPMENT_PROFILE_NAME)"

.PHONY: help gen test-core test-app test-app-beta test-mac-unit test-focus-mac test-mac test build-sim build-sim-beta build-sim-sandbox build-mac devices sandbox-profile check-xcode-beta check-device-signing-config check-device-config check-mac-signing-config build-device build-device-beta build-device-stable build-device-sandbox install-device install-device-beta install-device-stable install-device-sandbox check-release-config asc-check profile-create profile-create-dev profile-create-appstore profile-download profile-install profile-inspect profile-verify-cloudkit archive export-ipa publish-testflight

help: ## Show repeatable local, device, and TestFlight tasks.
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z0-9_.-]+:.*##/ {printf "  %-24s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

gen: ## Regenerate IntelliExpense.xcodeproj from project.yml.
	@xcodegen generate

test-core: ## Run ExpenseCore package tests.
	@cd ExpenseCore && swift test

test-app: ## Run app unit and UI tests on the standard iOS simulator.
	@xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(SIM_DEST)" test

test-app-beta: check-xcode-beta ## Compile the iOS 27 image path and run app tests on the configured simulator.
	@DEVELOPER_DIR="$(XCODE_BETA_DEVELOPER_DIR)" xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(SIM_DEST)" -derivedDataPath "$(BETA_DERIVED_DATA)" test XCODE_27_SWIFT_CONDITION=XCODE_27_FOUNDATION_MODELS

test-mac-unit: gen ## Run native Mac behavior tests locally without UI automation.
	@xcodebuild -project "$(PROJECT)" -scheme "$(MAC_SCHEME)" -destination "$(MAC_DEST)" test "-only-testing:IntelliExpenseMacTests" CODE_SIGNING_ALLOWED=NO

test-focus-mac: gen check-mac-signing-config ## Owner-explicit local fallback; set TEST=target/class[/method].
	@if [ -z "$(TEST)" ]; then printf "Set TEST=IntelliExpenseMacUITests/IntelliExpenseMacUITests/testMethod\n"; exit 2; fi
	@xcodebuild -project "$(PROJECT)" -scheme "$(MAC_SCHEME)" -destination "$(MAC_DEST)" test "-only-testing:$(TEST)" $(MAC_SIGNING_SETTINGS)

test-mac: gen check-mac-signing-config ## Owner-explicit local fallback for the full native Mac UI suite.
	@xcodebuild -project "$(PROJECT)" -scheme "$(MAC_SCHEME)" -destination "$(MAC_DEST)" test $(MAC_SIGNING_SETTINGS)

test: test-core test-app ## Run the full automated test gate.

build-sim: ## Build the app for the standard iOS simulator.
	@xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "$(SIM_DEST)" build

build-sim-beta: check-xcode-beta ## Compile the iOS 27 image path with the beta SDK without changing xcode-select.
	@DEVELOPER_DIR="$(XCODE_BETA_DEVELOPER_DIR)" xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -destination "generic/platform=iOS Simulator" -derivedDataPath "$(BETA_DERIVED_DATA)" build XCODE_27_SWIFT_CONDITION=XCODE_27_FOUNDATION_MODELS

build-sim-sandbox: gen ## Build the local-only sandbox app for the standard iOS simulator.
	@xcodebuild -project "$(PROJECT)" -scheme "$(SANDBOX_SCHEME)" -destination "$(SIM_DEST)" -derivedDataPath "$(SANDBOX_DERIVED_DATA)" build

build-mac: gen ## Build the native macOS app.
	@if [ -n "$(TEAM_ID)" ] && [ -n "$(DEVELOPMENT_SIGNING_IDENTITY)" ] && [ -n "$(MAC_DEVELOPMENT_PROFILE_NAME)" ]; then \
		xcodebuild -project "$(PROJECT)" -scheme "$(MAC_SCHEME)" -destination "$(MAC_DEST)" build $(MAC_SIGNING_SETTINGS); \
	else \
		xcodebuild -project "$(PROJECT)" -scheme "$(MAC_SCHEME)" -destination "$(MAC_DEST)" build CODE_SIGNING_ALLOWED=NO; \
	fi

devices: ## List paired devices and the Xcode hardware UDIDs accepted by DEVICE_ID.
	@xcrun devicectl list devices
	@printf "\nXcode build destinations (use the physical device id for DEVICE_ID):\n"
	@xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -showdestinations | sed -n '/platform:iOS, arch:arm64/p'

check-xcode-beta: ## Verify the scoped Xcode 27 beta toolchain exists.
	@test -x "$(XCODE_BETA_DEVELOPER_DIR)/usr/bin/xcodebuild" || { printf "Xcode 27 beta not found at %s\nSet XCODE_BETA_DIR=/path/to/Xcode-27-beta.app\n" "$(XCODE_BETA_DIR)"; exit 2; }
	@DEVELOPER_DIR="$(XCODE_BETA_DEVELOPER_DIR)" xcodebuild -checkFirstLaunchStatus

check-device-signing-config: ## Verify local target-specific signing values for a physical-device build.
	@if [ "$(DEVELOPMENT_CODE_SIGN_STYLE)" = "Manual" ] && { [ -z "$(DEVELOPMENT_SIGNING_IDENTITY)" ] || [ -z "$(DEVELOPMENT_PROFILE_NAME)" ] || [ -z "$(SHARE_DEVELOPMENT_PROFILE_NAME)" ] || [ -z "$(CONTROLS_DEVELOPMENT_PROFILE_NAME)" ]; }; then \
		printf "Manual signing requires DEVELOPMENT_SIGNING_IDENTITY and all three development profile names in Makefile.local\n"; exit 2; \
	fi

check-device-config: check-device-signing-config ## Verify the paired-device identifier and signing values.
	@if [ -z "$(DEVICE_ID)" ]; then printf "Set DEVICE_ID=<paired iPhone identifier> in Makefile.local\n"; exit 2; fi

check-mac-signing-config: ## Verify local values required by signed Mac UI-test lanes.
	@if [ -z "$(TEAM_ID)" ] || [ -z "$(DEVELOPMENT_SIGNING_IDENTITY)" ] || [ -z "$(MAC_DEVELOPMENT_PROFILE_NAME)" ]; then \
		printf "Set TEAM_ID, DEVELOPMENT_SIGNING_IDENTITY, and MAC_DEVELOPMENT_PROFILE_NAME in Makefile.local\n"; exit 2; \
	fi

sandbox-profile: ## Print the side-by-side sandbox lane agents should use.
	@printf "Sandbox scheme:    %s\n" "$(SANDBOX_SCHEME)"
	@printf "Sandbox bundle:    %s\n" "$(SANDBOX_BUNDLE_ID)"
	@printf "Sandbox app:       %s\n" "$(SANDBOX_APP_TARGET)"
	@printf "Sandbox data:      local SwiftData only; CloudKit/App Group OFF\n"
	@printf "Seed data:         generic App Store screenshot-safe trips and synthetic receipts\n"
	@printf "Reset by default:  SANDBOX_UNINSTALL_FIRST=%s\n" "$(SANDBOX_UNINSTALL_FIRST)"
	@printf "Install command:   make install-device-sandbox\n"

check-release-config: ## Verify bundle ID, team, iPhone gate, display name, and iCloud container.
	@if [ -z "$(TEAM_ID)" ]; then printf "Set TEAM_ID in Makefile.local or the environment\n"; exit 2; fi
	@settings="$$(xcodebuild -project "$(PROJECT)" -target "$(APP_TARGET)" -configuration Release DEVELOPMENT_TEAM="$(TEAM_ID)" -showBuildSettings 2>/dev/null)"; \
	printf "%s\n" "$$settings" | grep -q "PRODUCT_BUNDLE_IDENTIFIER = $(BUNDLE_ID)" || { printf "Expected PRODUCT_BUNDLE_IDENTIFIER = $(BUNDLE_ID)\n"; exit 1; }; \
	printf "%s\n" "$$settings" | grep -q "DEVELOPMENT_TEAM = $(TEAM_ID)" || { printf "Expected DEVELOPMENT_TEAM = $(TEAM_ID)\n"; exit 1; }; \
	printf "%s\n" "$$settings" | grep -q "TARGETED_DEVICE_FAMILY = 1" || { printf "Expected TARGETED_DEVICE_FAMILY = 1\n"; exit 1; }
	@display_name="$$(/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" IntelliExpense/Info.plist)"; \
	test "$$display_name" = "Intelli-Expense" || { printf "Expected CFBundleDisplayName = Intelli-Expense\n"; exit 1; }
	@cap0="$$(/usr/libexec/PlistBuddy -c "Print :UIRequiredDeviceCapabilities:0" IntelliExpense/Info.plist)"; \
	cap1="$$(/usr/libexec/PlistBuddy -c "Print :UIRequiredDeviceCapabilities:1" IntelliExpense/Info.plist)"; \
	test "$$cap0" = "arm64" || { printf "Expected UIRequiredDeviceCapabilities[0] = arm64\n"; exit 1; }; \
	test "$$cap1" = "iphone-performance-gaming-tier" || { printf "Expected UIRequiredDeviceCapabilities[1] = iphone-performance-gaming-tier\n"; exit 1; }
	@container="$$(/usr/libexec/PlistBuddy -c "Print :com.apple.developer.icloud-container-identifiers:0" IntelliExpense/IntelliExpense.entitlements)"; \
	test "$$container" = "$(CLOUDKIT_CONTAINER)" || { printf "Expected CloudKit container = $(CLOUDKIT_CONTAINER)\n"; exit 1; }
	@app_group="$$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.application-groups:0" IntelliExpense/IntelliExpense.entitlements)"; \
	test "$$app_group" = "group.com.nags.intelliexpense" || { printf "Expected App Group = group.com.nags.intelliexpense\n"; exit 1; }
	@share_group="$$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.application-groups:0" IntelliExpenseShare/IntelliExpenseShare.entitlements)"; \
	test "$$share_group" = "group.com.nags.intelliexpense" || { printf "Expected share App Group = group.com.nags.intelliexpense\n"; exit 1; }
	@printf "Release config OK for $(BUNDLE_ID)\n"

build-device: check-device-config check-release-config check-xcode-beta ## Build the durable iPhone app with the default Xcode 27 beta lane.
	@DEVELOPER_DIR="$(XCODE_BETA_DEVELOPER_DIR)" xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Debug -destination "platform=iOS,id=$(DEVICE_ID)" -derivedDataPath "$(BETA_DERIVED_DATA)" build DEVELOPMENT_TEAM="$(TEAM_ID)" XCODE_27_SWIFT_CONDITION=XCODE_27_FOUNDATION_MODELS $(DEVICE_SIGNING_SETTINGS)

build-device-beta: build-device ## Compatibility alias for the default Xcode 27 beta device build.

build-device-stable: check-release-config check-device-signing-config ## Build the durable iPhone app with the machine's stable Xcode.
	@xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Debug -destination "generic/platform=iOS" -derivedDataPath "$(DERIVED_DATA)" build DEVELOPMENT_TEAM="$(TEAM_ID)" $(DEVICE_SIGNING_SETTINGS)

install-device: build-device ## Build and install the durable app with Xcode 27 beta without resetting data.
	@DEVELOPER_DIR="$(XCODE_BETA_DEVELOPER_DIR)" xcrun devicectl device install app --device "$(DEVICE_ID)" "$(BETA_DERIVED_DATA)/Build/Products/Debug-iphoneos/$(APP_TARGET).app"

install-device-beta: install-device ## Compatibility alias for the default Xcode 27 beta device install.

install-device-stable: check-device-config check-release-config ## Build and install with stable Xcode without uninstalling existing data.
	@xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Debug -destination "platform=iOS,id=$(DEVICE_ID)" -derivedDataPath "$(DERIVED_DATA)" build DEVELOPMENT_TEAM="$(TEAM_ID)" $(DEVICE_SIGNING_SETTINGS)
	@xcrun devicectl device install app --device "$(DEVICE_ID)" "$(DERIVED_DATA)/Build/Products/Debug-iphoneos/$(APP_TARGET).app"

build-device-sandbox: gen ## Build the side-by-side sandbox app for a physical iPhone.
	@if [ -z "$(DEVICE_ID)" ]; then printf "Set DEVICE_ID=<paired iPhone identifier>\n"; exit 2; fi
	@xcodebuild -project "$(PROJECT)" -scheme "$(SANDBOX_SCHEME)" -configuration Debug -destination "platform=iOS,id=$(DEVICE_ID)" -derivedDataPath "$(SANDBOX_DERIVED_DATA)" build DEVELOPMENT_TEAM="$(TEAM_ID)" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates

install-device-sandbox: build-device-sandbox ## Reset, install, seed, and launch the sandbox app side-by-side with the main app.
	@if [ "$(SANDBOX_UNINSTALL_FIRST)" = "1" ]; then xcrun devicectl device uninstall app --device "$(DEVICE_ID)" "$(SANDBOX_BUNDLE_ID)" >/dev/null 2>&1 || true; fi
	@xcrun devicectl device install app --device "$(DEVICE_ID)" "$(SANDBOX_DERIVED_DATA)/Build/Products/Debug-iphoneos/$(SANDBOX_APP_TARGET).app"
	@xcrun devicectl device process launch --device "$(DEVICE_ID)" --terminate-existing "$(SANDBOX_BUNDLE_ID)" >/dev/null
	@printf "Installed and launched %s with seeded local sandbox data. Main app bundle %s was not touched.\n" "$(SANDBOX_BUNDLE_ID)" "$(BUNDLE_ID)"

asc-check: ## Read back the App Store app, TestFlight groups, and recent builds.
	@asc apps view --id "$(ASC_APP_ID)" --output json
	@asc testflight groups list --app "$(ASC_APP_ID)" --output json
	@asc builds list --app "$(ASC_APP_ID)" --limit 5 --output json

profile-create: profile-create-appstore ## Create the App Store provisioning profile in App Store Connect.

profile-create-dev: ## Create the phone-install development provisioning profile.
	@asc profiles create --name "$(DEVELOPMENT_PROFILE_NAME)" --profile-type IOS_APP_DEVELOPMENT --bundle "$(BUNDLE_RESOURCE_ID)" --certificate "$(DEVELOPMENT_CERTIFICATE_ID)" --device "$(ASC_DEVICE_ID)" --output json

profile-create-appstore: ## Create the App Store provisioning profile in App Store Connect.
	@asc profiles create --name "$(DISTRIBUTION_PROFILE_NAME)" --profile-type IOS_APP_STORE --bundle "$(BUNDLE_RESOURCE_ID)" --certificate "$(DISTRIBUTION_CERTIFICATE_ID)" --output json

profile-download: ## Download PROFILE_ID to build/profiles.
	@if [ -z "$(PROFILE_ID)" ]; then printf "Set PROFILE_ID=<App Store profile id>\n"; exit 2; fi
	@mkdir -p build/profiles
	@asc profiles download --id "$(PROFILE_ID)" --output "build/profiles/$(PROFILE_ID).mobileprovision"

profile-install: profile-download ## Install PROFILE_ID into Xcode's local profiles directory.
	@asc profiles local install --path "build/profiles/$(PROFILE_ID).mobileprovision"

profile-inspect: ## Inspect a downloaded profile file: make profile-inspect PROFILE=path.mobileprovision.
	@if [ -z "$(PROFILE)" ]; then printf "Set PROFILE=<path.mobileprovision>\n"; exit 2; fi
	@asc profiles inspect --path "$(PROFILE)"

profile-verify-cloudkit: ## Fail unless PROFILE includes the configured CloudKit container.
	@if [ -z "$(PROFILE)" ]; then printf "Set PROFILE=<path.mobileprovision>\n"; exit 2; fi
	@asc profiles inspect --path "$(PROFILE)" --output json | jq -e --arg container "$(CLOUDKIT_CONTAINER)" '.entitlements["com.apple.developer.icloud-container-identifiers"] // [] | index($$container)' >/dev/null || { printf "Profile missing CloudKit container $(CLOUDKIT_CONTAINER)\n"; exit 1; }
	@printf "Profile includes CloudKit container $(CLOUDKIT_CONTAINER)\n"

archive: check-release-config ## Create a signed App Store Connect archive.
	@mkdir -p "$(dir $(ARCHIVE_PATH))"
	@xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Release -destination "generic/platform=iOS" -archivePath "$(ARCHIVE_PATH)" archive DEVELOPMENT_TEAM="$(TEAM_ID)" $(RELEASE_SIGNING_SETTINGS)

export-ipa: ## Export the archived app as an App Store Connect IPA.
	@mkdir -p "$(EXPORT_PATH)"
	@xcodebuild -exportArchive -archivePath "$(ARCHIVE_PATH)" -exportPath "$(EXPORT_PATH)" -exportOptionsPlist "$(EXPORT_OPTIONS)" -allowProvisioningUpdates

publish-testflight: ## Upload IPA to the internal TestFlight group.
	@if [ -z "$(TESTFLIGHT_GROUP_ID)" ]; then printf "Set TESTFLIGHT_GROUP_ID=<internal group id>\n"; exit 2; fi
	@asc publish testflight --app "$(ASC_APP_ID)" --ipa "$(IPA)" --group "$(TESTFLIGHT_GROUP_ID)" --wait --output json
