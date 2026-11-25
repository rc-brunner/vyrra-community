# Meetings

Open **Meetings** and choose the calendar-plus button. On macOS you can pick from Apple Calendar. On either platform you can import an `.ics` file. For an invitation with attendees, enter your calendar email to show accepted invitations. Select the occurrence, choose how to join and confirm. A file import is a snapshot. Cancel and reselect the occurrence if the organizer changes it. Apple Calendar plans follow updates while Vyrra is running.

## On this computer

Install the speech model in **Dictate**. In **Settings → Meetings**, select the calling app on macOS. On Windows the input is system output. Vyrra opens the selected call and shows a floating stop button at the scheduled time. It uses the microphone and the chosen application’s audio on macOS, including other tabs in that app, or all output on Windows. Tell participants before the scheduled capture. Normal provider sign-in and host admission still apply. Keep Vyrra and the computer awake. Use the stop button when you leave early. Saved transcript text stays on the device. The optional local writing model can produce a summary, decisions and proposed action items from the transcript. Review the output before sharing.

## Self-hosted participant

Run an Attendee server with its API, scheduler, database, worker and the meeting provider configuration you intend to use. Follow the upstream deployment and authentication instructions. [Attendee self-hosting](https://github.com/attendee-labs/attendee)

In **Settings → Meetings**, enter your server origin and import a text file containing its API key. The app puts the key in Keychain on macOS or Credential Manager on Windows. An HTTPS endpoint allows you to use a separate server. Loopback HTTP works for local development.

Set a display name. Hover over or focus the avatar to choose a PNG or JPEG. The reset icon restores Vyrra’s mark. The identity is captured when you schedule a participant. During scheduling Vyrra sends the name, cropped image, join time and selected meeting link to your server. Once scheduled, the server can join while the desktop is closed. It sends a note-taking disclosure to meeting chat, requests meeting captions and disables saved media. The provider controls guest entry, captions and how the bot image appears. Some organizations disable guests, chat or captions. An unavailable caption stream can produce an empty transcript. [Scheduled participants](https://github.com/attendee-labs/attendee/blob/main/docs/scheduled_bots.md)

Use the refresh icon on the meeting to retrieve current status and notes. Stop or cancel acts on the server. Deleting a finished meeting in Vyrra removes its local copy. The server operator controls retention of the server copy.
