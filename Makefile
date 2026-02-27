APP_NAME := ClaudeAgentConnector

.PHONY: generate-project debug-build release clean

generate-project:
	@xcodegen generate --spec project.yml

debug-build: generate-project
	@xcodebuild \
		-project $(APP_NAME).xcodeproj \
		-scheme $(APP_NAME) \
		-configuration Debug \
		-destination "platform=macOS" \
		clean build \
		CODE_SIGNING_ALLOWED=NO

release:
	@./scripts/build_release.sh

clean:
	@rm -rf .build dist $(APP_NAME).xcodeproj
