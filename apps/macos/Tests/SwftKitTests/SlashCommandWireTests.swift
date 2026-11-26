import Foundation
import Testing
@testable import SwftKit

@Suite("Slash Commands & Skills Wire Models")
struct SlashCommandWireTests {
    @Test func decodesProviderSlashCommandsSkillsAndWorkspaceSnapshots() throws {
        let decoder = SwftJSON.makeDecoder()
        let eventJSON = """
        {
          "version": 1,
          "type": "snapshot",
          "config": {
            "environment": {
              "environmentId": "env-local",
              "label": "Local Mac",
              "platform": { "os": "darwin", "arch": "arm64", "machine": "laptop" },
              "serverVersion": "0.2.0",
              "orchestrationProtocolVersion": 2,
              "capabilities": {
                "freshContext": true,
                "providerWorkspaceSnapshotsOnDemand": true
              }
            },
            "auth": {
              "policy": "desktop-managed-local",
              "bootstrapMethods": ["desktop-bootstrap"],
              "sessionMethods": ["bearer-access-token"],
              "sessionCookieName": "t3_session"
            },
            "cwd": "/Users/dev/project",
            "providers": [
              {
                "instanceId": "antigravity",
                "driver": "antigravity",
                "displayName": "Antigravity",
                "enabled": true,
                "installed": true,
                "status": "ready",
                "auth": { "status": "authenticated" },
                "checkedAt": "2026-11-25T20:00:00.000Z",
                "models": [
                  {
                    "slug": "gemini-4-neon",
                    "name": "Gemini 4 Neon",
                    "isCustom": false
                  }
                ],
                "slashCommands": [
                  {
                    "name": "learn",
                    "description": "Persist corrections for future tasks",
                    "input": { "hint": "topic or rule" }
                  },
                  {
                    "name": "compact",
                    "description": "Summarize context to free window"
                  },
                  {
                    "name": "boost"
                  }
                ],
                "skills": [
                  {
                    "name": "test-t3-app",
                    "description": "Verify UI through built-in Browser panel",
                    "shortDescription": "Verify web UI",
                    "displayName": "Test T3 App",
                    "path": "/Users/dev/project/.agents/skills/test-t3-app/SKILL.md",
                    "scope": "repo",
                    "enabled": true,
                    "userInvocationOnly": true
                  },
                  {
                    "name": "agent-only",
                    "path": "/Users/dev/project/.agents/skills/agent-only/SKILL.md",
                    "enabled": true,
                    "userInvocable": false
                  },
                  {
                    "name": "disabled-skill",
                    "path": "/Users/dev/project/.agents/skills/disabled/SKILL.md",
                    "enabled": false
                  }
                ],
                "workspaceRescannedAt": "2026-11-25T20:01:00.000Z",
                "workspaceSnapshots": [
                  {
                    "cwd": "/Users/dev/project",
                    "checkedAt": "2026-11-25T20:01:00.000Z",
                    "slashCommands": [
                      {
                        "name": "learn",
                        "description": "Workspace learn command",
                        "input": { "hint": "rule" }
                      },
                      {
                        "name": "deploy-staging",
                        "description": "Deploy staging build"
                      }
                    ],
                    "slashCommandsPending": false,
                    "skills": [
                      {
                        "name": "workspace-skill",
                        "path": "/Users/dev/project/.agents/skills/workspace-skill/SKILL.md",
                        "scope": "project",
                        "enabled": true
                      }
                    ]
                  }
                ]
              }
            ]
          }
        }
        """

        let event = try decoder.decode(ServerConfigStreamEvent.self, from: Data(eventJSON.utf8))
        guard case .snapshot(let config) = event else {
            Issue.record("Expected snapshot event")
            return
        }

        #expect(config.environment.capabilities.freshContext == true)
        #expect(config.providers.count == 1)

        let provider = config.providers[0]
        #expect(provider.slashCommands.count == 3)
        #expect(provider.slashCommands[0].name == "learn")
        #expect(provider.slashCommands[0].description == "Persist corrections for future tasks")
        #expect(provider.slashCommands[0].input?.hint == "topic or rule")
        #expect(provider.slashCommands[1].input == nil)
        #expect(provider.slashCommands[2].name == "boost")
        #expect(provider.slashCommands[2].description == nil)

        #expect(provider.skills.count == 3)
        #expect(provider.skills[0].isUserInvocable == true)
        #expect(provider.skills[0].userInvocationOnly == true)
        #expect(provider.skills[0].resolvedDisplayName == "Test T3 App")
        #expect(provider.skills[1].isUserInvocable == false)
        #expect(provider.skills[2].isUserInvocable == false)

        #expect(provider.workspaceRescannedAt != nil)
        #expect(provider.workspaceSnapshots?.count == 1)
        #expect(provider.workspaceSnapshot(for: "/Users/dev/project")?.isPending == false)

        // CWD resolution prefers matching workspace snapshot and falls back to machine catalog otherwise.
        let workspaceCommands = provider.resolvedSlashCommands(for: "/Users/dev/project")
        #expect(workspaceCommands.map(\.name) == ["learn", "deploy-staging"])
        let workspaceSkills = provider.resolvedSkills(for: "/Users/dev/project")
        #expect(workspaceSkills.map(\.name) == ["workspace-skill"])

        let fallbackCommands = provider.resolvedSlashCommands(for: "/Users/dev/other")
        #expect(fallbackCommands.map(\.name) == ["learn", "compact", "boost"])
        let fallbackSkills = provider.resolvedSkills(for: nil)
        #expect(fallbackSkills.count == 3)
    }

    @Test func legacyProviderWithoutSlashCommandsOrSkillsDefaultsToEmpty() throws {
        let decoder = SwftJSON.makeDecoder()
        let json = """
        {
          "instanceId": "claudeAgent",
          "driver": "claudeAgent",
          "displayName": "Claude",
          "enabled": true,
          "installed": true,
          "status": "ready",
          "auth": { "status": "authenticated" },
          "checkedAt": "2026-11-25T20:00:00.000Z",
          "models": []
        }
        """

        let provider = try decoder.decode(ServerProvider.self, from: Data(json.utf8))
        #expect(provider.slashCommands.isEmpty)
        #expect(provider.skills.isEmpty)
        #expect(provider.workspaceSnapshots == nil)
        #expect(provider.workspaceRescannedAt == nil)
    }

    @Test func dispatchMessageEncodesFreshContextWhenProvided() throws {
        let encoder = SwftJSON.makeEncoder()

        let freshCommand = OrchestrationCommand.dispatchMessage(
            commandId: "cmd-1",
            threadId: "thr-1",
            messageId: "msg-1",
            text: "Start fresh",
            freshContext: true
        )
        let freshData = try encoder.encode(freshCommand)
        let freshJSON = try JSONDecoder().decode(JSONValue.self, from: freshData)
        #expect(freshJSON["freshContext"] == .bool(true))

        let normalCommand = OrchestrationCommand.dispatchMessage(
            commandId: "cmd-2",
            threadId: "thr-1",
            messageId: "msg-2",
            text: "Continue"
        )
        let normalData = try encoder.encode(normalCommand)
        let normalJSON = try JSONDecoder().decode(JSONValue.self, from: normalData)
        #expect(normalJSON["freshContext"] == nil)
    }
}
