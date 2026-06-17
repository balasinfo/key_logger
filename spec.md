Objective
Create a macOS application that records keyboard input, browser activity, and application usage for personal productivity analysis, research, or self-monitoring purposes. The tool should demonstrate responsible data handling practices and serve as a reference implementation for developers interested in system-level event monitoring on macOS.

Target Platform
macOS (Intel and Apple Silicon)

Primary Technology Stack Recommendation

Swift + SwiftUI (for the main application and UI)
Combine or async/await for event handling
Optional Node.js/Electron layer for cross-platform extensibility or backend logging components (if desired)
Core Graphics / CGEventTap or Accessibility APIs for low-level input monitoring
Core Functional Requirements

Keyboard Input Logging
Capture all key-down and key-up events system-wide
Record printable characters, space, enter/return, modifiers, and special keys
Timestamp each event with high precision
Store raw and processed representations (e.g., character vs. key code)
Browser Activity Monitoring
Detect active browser applications (Safari, Chrome, Firefox, Edge)
Capture current URL/title when the browser window or tab changes
Record navigation events where possible (with user permission)
Log timestamps for URL visits
Application and Window Usage Tracking
Monitor foreground application switches
Record active window titles for supported applications
Track duration spent in each application
Specifically identify and log gaming sessions when games are detected in the foreground
YouTube and Media Tracking
Detect when YouTube is active in a browser
Capture video titles and video IDs where technically feasible
Log start and end times of video playback sessions
Data Storage
Use a local SQLite database or structured JSON/Plist files for storage
Include timestamps, event type, source application, and metadata
Provide options for data export (CSV, JSON)
User Interface
Simple dashboard showing recent activity summary
Toggle to pause/resume logging
Settings screen for data retention period and export options
Clear indication that the application is running and logging
Permissions and Security
Request Accessibility permissions (required for CGEventTap)
Request Automation permissions for browser URL access where needed
Display clear consent screens explaining what data is collected
Include a visible status indicator when logging is active
Non-Functional Requirements

Run efficiently with low CPU and memory impact
Respect macOS privacy and sandboxing guidelines
Include comprehensive logging of the logger itself for debugging
Support graceful handling of permission changes or revocations
Development Phases Suggestion

Basic keystroke capture using CGEventTap
Application and window monitoring
Browser URL detection integration
Data persistence layer
User interface and settings
YouTube-specific enhancements and gaming detection
Important Notes for Responsible Development

The application should clearly inform users that it records input and activity.
All data should remain local unless the user explicitly enables export or synchronization.
Include prominent warnings and consent flows before enabling full logging.
