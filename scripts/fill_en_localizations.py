#!/usr/bin/env python3
"""Merge English stringUnit into Localizable.xcstrings for keys missing en."""
import json
import sys
from pathlib import Path

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from en_supplement import EN_SUPPLEMENT

CAT = Path(__file__).resolve().parents[1] / "Fanfolio" / "Localizable.xcstrings"

# key -> English value (preserve %@, %lld, %1$@, positional specifiers, \n)
EN: dict[str, str] = {
    "api.error.dailyLimitExceeded": "Today’s API call limit (100) has been exceeded. Try again tomorrow.",
    "api.error.decodingFailedFormat": "Data parsing error: %@",
    "api.error.invalidURL": "Invalid API URL.",
    "api.error.networkErrorFormat": "Network error: %@",
    "api.error.noAPIKey": "No API key set. Copy APIKeys.xcconfig.example to APIKeys.xcconfig in the project root, add API_SPORTS_KEY, then rebuild.",
    "api.error.noData": "No data available.",
    "auth.continueAsGuest": "Continue without signing in",
    "auth.feature.cultureArchive": "Archive concerts, musicals, and more",
    "auth.feature.shareTickets": "Share memories with ticket images",
    "auth.feature.sportsRecord": "Log games you attend and track win rate",
    "auth.guestModeDisclaimer": "You can use all features without signing in.\niCloud sync works automatically from device settings.",
    "auth.profile.appleID": "Apple ID",
    "auth.profile.guestBadge": "Guest",
    "auth.profile.guestName": "Guest",
    "auth.profile.userFallback": "User",
    "auth.tagline": "Your personal fan archive",
    "category.sidebar.section.culture": "Culture",
    "category.sidebar.section.sports": "Sports",
    "common.action.cancel": "Cancel",
    "common.action.close": "Close",
    "common.action.create": "Create",
    "common.action.delete": "Delete",
    "common.action.done": "Done",
    "common.action.edit": "Edit",
    "common.action.ok": "OK",
    "common.action.retry": "Try Again",
    "common.action.save": "Save",
    "common.action.share": "Share",
    "common.action.viewDetails": "View details",
    "common.filter.all": "All",
    "error.image.readFailed": "Could not read image data.",
    "error.image.saveFailed": "Could not save the image.",
    "error.load.generic": "Something went wrong while loading data.",
    "error.storage.documentsUnavailable": "Documents storage is not available.",
    "espn.error.unsupportedLeagueFormat": "ESPN does not support the ‘%@’ league.",
    "matchImport.empty.pastDescription": "No completed games found for ‘%@’.",
    "matchImport.empty.pastTitle": "No past games",
    "matchImport.empty.upcomingDescription": "No upcoming games found for ‘%@’.",
    "matchImport.empty.upcomingTitle": "No upcoming games",
    "matchImport.error.emptyScheduleFormat": "Could not load the schedule for ‘%@’.",
    "matchImport.error.loadFailedFormat": "Could not load games.\n%@",
    "matchImport.error.title": "Import failed",
    "matchImport.error.unsupportedLeague": "This league does not support schedule import.\n(Supported: NFL, NBA, MLB, EPL and other ESPN leagues, KBO)",
    "matchImport.footer.pastHint": "Tap a game to add it to your archive. Already added games show a checkmark.",
    "matchImport.footer.upcomingHint": "Tap an upcoming game to add it to your schedule. Enter the result yourself after the game.",
    "matchImport.loading": "Loading games…",
    "matchImport.navigationTitle": "Import games",
    "matchImport.picker.accessibility": "Tab selection",
    "matchImport.section.recentResults": "Recent results (up to 5 games)",
    "matchImport.section.upcomingSchedule": "Upcoming schedule (up to 5 games)",
    "network.connection.cellular": "Cellular",
    "network.connection.other": "Other",
    "network.connection.unknown": "Unknown",
    "network.error.noConnection": "No internet connection. Connect and try again.",
    "player.phase.nfl.defense": "Defense",
    "player.phase.nfl.offense": "Offense",
    "player.phase.nfl.specialTeams": "Special teams",
    "player.position.baseball.catcher": "Catcher",
    "player.position.baseball.designatedHitter": "Designated hitter",
    "player.position.baseball.infielder": "Infielder",
    "player.position.baseball.outfielder": "Outfielder",
    "player.position.baseball.pitcher": "Pitcher",
    "player.position.basketball.center": "Center",
    "player.position.basketball.forward": "Forward",
    "player.position.basketball.guard": "Guard",
    "player.position.nfl.special": "Special teams",
    "player.position.soccer.defender": "Defender",
    "player.position.soccer.forward": "Forward",
    "player.position.soccer.goalkeeper": "Goalkeeper",
    "player.position.soccer.midfielder": "Midfielder",
    "player.position.unknown": "Other",
    "playerList.count.players": "%lld players",
    "playerList.filter.all": "All",
    "scoreboard.inning.labelFormat": "%lld",
    "scoreboard.period.firstHalf": "1st half",
    "scoreboard.period.secondHalf": "2nd half",
    "settings.about.version": "Version",
    "settings.account.appleID": "Apple ID",
    "settings.account.connected": "Connected",
    "settings.account.deleteAccount": "Delete account",
    "settings.account.disconnected": "Not connected",
    "settings.account.footer.iCloud": "iCloud sync uses your device’s iCloud account. Check Settings > Apple ID > iCloud.",
    "settings.account.iCloudSync": "iCloud sync",
    "settings.account.signInStatus": "Sign-in",
    "settings.account.signOut": "Sign out",
    "settings.deleteAccount.title": "Delete account",
    "settings.logout.title": "Sign out",
    "settings.navigationTitle": "Settings",
    "settings.profile.emailLabel": "Email",
    "settings.profile.guest": "Guest",
    "settings.profile.nameField": "Name",
    "settings.profile.nameLabel": "Name",
    "settings.profile.nameUnset": "Not set",
    "settings.section.about": "About",
    "settings.section.account": "Account",
    "settings.section.profile": "Profile",
    "sidebar.folder.delete.cultureMessage": "The folder ‘%1$@’ and %2$lld record(s) will be deleted. This can’t be undone.",
    "sidebar.folder.delete.sportsMessage": "The folder ‘%1$@’ and %2$lld game record(s) will be deleted. This can’t be undone.",
    "sidebar.folder.delete.title": "Delete folder",
    "sports.card.dDay.countdown": "D-%lld",
    "sports.card.dDay.today": "D-Day",
    "sports.card.liveBadge": "LIVE",
    "sports.card.vs": "VS",
    "sports.folder.combinedName.header": "Team / folder name",
    "sports.folder.defaultName.leagueWatch": "Watching %@",
    "sports.folder.editTitle": "Edit folder",
    "sports.folder.footer.freeNameWithLeague": "Enter a player name or folder name you like.",
    "sports.folder.footer.playerOrEvent": "Enter a player you cheer for or an event you follow.",
    "sports.folder.footer.teamOrInterest": "Enter your team or what you’re interested in.",
    "sports.folder.footer.teamPickerHint": "Tap a team to fill in the name. Skip teams if you don’t have one—you can still pick opponents when adding games with only a league selected.",
    "sports.folder.matchType.footer.solo": "For solo events like marathons or swimming. You can’t change this after creation.",
    "sports.folder.matchType.footer.withOpponent": "For matchups like tennis or UFC.",
    "sports.folder.matchType.header": "Game type",
    "sports.folder.matchType.picker": "Game type",
    "sports.folder.matchType.solo": "No opponent",
    "sports.folder.matchType.withOpponent": "Has opponent",
    "sports.folder.name.field": "Folder name",
    "sports.folder.name.header": "Folder name",
    "sports.folder.newTitle": "New folder",
    "sports.folder.nickname.footer": "If set, this nickname appears on cards and detail instead of the official team name.",
    "sports.folder.nickname.header": "Team nickname (optional)",
    "sports.folder.nickname.placeholder": "e.g. 49ers, Ninjas",
    "sports.folder.placeholder.otherSport": "e.g. tennis match, boxing",
    "sports.folder.placeholder.teamExamples": "e.g. LG Twins, FC Seoul",
    "sports.folder.placeholder.withLeague": "e.g. %@ games, LG Twins",
    "sports.folder.section.league": "Choose league",
    "sports.folder.section.sportType": "Sport",
    "sports.folder.section.team": "Choose team",
    "sports.match.date": "Date",
    "sports.match.dateLocationSection": "Date & place",
    "sports.match.homeGame": "Home game",
    "sports.match.infoSection": "Game info",
    "sports.match.locationOptional": "Venue (optional)",
    "sports.match.memo.placeholder": "Notes, highlights…",
    "sports.match.memoSection": "Notes",
    "sports.match.myTeam": "My team",
    "sports.match.opponentTeam": "Opponent",
    "sports.match.photos.addFirst": "Add game photos",
    "sports.match.photos.addMore": "Add photos (%lld/10)",
    "sports.match.photos.footer": "Save stadium shots, selfies, food—up to 10 photos.",
    "sports.match.photos.header": "Game photos",
    "sports.match.result": "Result",
    "sports.match.scoreSection": "Score",
    "sports.match.status.footer": "Use ‘Scheduled’ before the game and ‘Completed’ after.",
    "sports.match.status.picker": "Game status",
    "sports.match.team1": "Team 1",
    "sports.match.team2": "Team 2",
    "sports.match.teamPicker.footer.sameLeague": "Tap a team from the same league.",
    "sports.match.teamPicker.footer.twoTeams": "Tap each team that played.",
    "sports.match.time": "Time",
    "sports.match.timeToggle": "Set time",
    "sports.stats.archetype.homeGuardian.subtitle": "We win at home",
    "sports.stats.archetype.homeGuardian.title": "Home guardian",
    "sports.stats.archetype.luckyFan.subtitle": "We win when I’m there",
    "sports.stats.archetype.luckyFan.title": "Lucky fan",
    "sports.stats.archetype.neverGiveUp.subtitle": "Never give up, even in defeat",
    "sports.stats.archetype.neverGiveUp.title": "Die-hard fan",
    "sports.stats.archetype.passionate.subtitle": "The stadium is my second home",
    "sports.stats.archetype.passionate.title": "Superfan",
    "sports.stats.archetype.rising.subtitle": "Growing your game-day game",
    "sports.stats.archetype.rising.title": "Rising fan",
    "sports.stats.archetype.roadWarrior.subtitle": "A real fan who travels",
    "sports.stats.archetype.roadWarrior.title": "Road warrior",
    "sports.stats.gamesPlayedFormat": "%lld games",
    "sports.stats.highlight.bestWin": "Best win",
    "sports.stats.highlight.mostGoals": "Most goals",
    "sports.stats.highlight.shutout": "Shutout",
    "sports.stats.label.draw": "D",
    "sports.stats.label.loss": "L",
    "sports.stats.label.win": "W",
    "sports.stats.lucky.battling.subtitle": "Charging toward victory!",
    "sports.stats.lucky.battling.title": "Battling fan",
    "sports.stats.lucky.blessed.subtitle": "Pretty solid game-day luck!",
    "sports.stats.lucky.blessed.title": "Blessed fan",
    "sports.stats.lucky.fortunate.subtitle": "We win when I show up!",
    "sports.stats.lucky.fortunate.title": "Fortunate fan",
    "sports.stats.lucky.indomitable.subtitle": "True fans cheer through losses",
    "sports.stats.lucky.indomitable.title": "Unbreakable fan",
    "sports.stats.lucky.legendary.subtitle": "We always win when I’m there!",
    "sports.stats.lucky.legendary.title": "Legendary lucky fan",
    "sports.stats.lucky.trial.subtitle": "Rainbows come after rain",
    "sports.stats.lucky.trial.title": "Tested fan",
    "sports.stats.record.winLossDraw": "%1$lldW %2$lldL %3$lldD",
    "sports.stats.share.seasonWatermark": "FANFOLIO  SEASON %lld",
    "ticket.error.saveImageFailed": "Could not save the ticket image.",
    "ticket.error.thumbnailFailed": "Could not create ticket thumbnail.",
    "ticket.gallery.delete.message": "Remove this ticket from the gallery. Saved image files will be deleted too.",
    "ticket.gallery.delete.title": "Delete ticket",
    "ticket.gallery.empty.description": "Save ticket images from game detail to see them here.",
    "ticket.gallery.empty.title": "No saved tickets",
    "ticket.gallery.error.imageMissing": "The original ticket image couldn’t be found on this device.",
    "ticket.gallery.filteredEmpty.description": "Try another sport filter.",
    "ticket.gallery.filteredEmpty.title": "No tickets match",
    "ticket.gallery.navigationTitle": "Ticket gallery",
    "ticket.gallery.shareUnavailable.title": "Can’t share",
    "ticket.gallery.sidebarEntry": "Ticket gallery",
    "ticket.overlay.charCount": "%lld/20",
    "ticket.overlay.placeholder": "Type something here",
    "ticket.share.error.genericSaveFailedReason": "Couldn’t save.\n%@",
    "ticket.share.error.photoAccessRequired": "Photo access is required. Allow it in Settings.",
    "ticket.share.error.renderFailed": "Couldn’t create the ticket image.",
    "ticket.share.error.saveFailedReason": "Couldn’t save the ticket.\n%@",
    "ticket.share.toast.savedToGallery": "Saved to your gallery.",
    "ticket.share.toast.savedToPhotos": "Saved to Photos.",
}


def _apply_en(strings: dict, key: str, en_value: str) -> None:
    locs = strings[key].setdefault("localizations", {})
    locs["en"] = {
        "stringUnit": {
            "state": "translated",
            "value": en_value,
        }
    }


def main() -> None:
    data = json.loads(CAT.read_text(encoding="utf-8"))
    strings = data.get("strings", {})

    applied = 0
    for key, en_value in EN.items():
        if key not in strings:
            continue
        _apply_en(strings, key, en_value)
        applied += 1

    sup = 0
    for key, en_value in EN_SUPPLEMENT.items():
        if key not in strings:
            raise SystemExit(f"EN_SUPPLEMENT key not in catalog: {key!r}")
        locs = strings[key].get("localizations") or {}
        en = locs.get("en", {}).get("stringUnit", {})
        if en.get("state") == "translated":
            continue
        _apply_en(strings, key, en_value)
        sup += 1

    CAT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Updated {applied} keys from EN, {sup} from EN_SUPPLEMENT → {CAT}")


if __name__ == "__main__":
    main()
