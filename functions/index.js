const {onSchedule} = require("firebase-functions/v2/scheduler");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");
const axios = require("axios");
const crypto = require("crypto");

const apiSportsKey = defineSecret("API_SPORTS_KEY");
if (!admin.apps.length) {
  admin.initializeApp();
}

const KBO_LEAGUE_ID = 5;
const KBO_SEASON = new Date().getFullYear();
const BASE_URL = "https://v1.baseball.api-sports.io";

/** 비시즌·새벽 포함 저빈도 백업 (연중) */
exports.fetchKboNight = onSchedule({
  schedule: "0 15,17,19,21,23,1,3 * * *",
  timeZone: "UTC",
  secrets: [apiSportsKey],
}, async (event) => {
  try {
    await syncKBO(apiSportsKey.value());
  } catch (err) {
    console.error("KBO 동기화 실패:", err.message || String(err));
  }
});

/** 시즌 중 오전·점심대 (UTC) — 경기 전 스케줄 반영용 */
exports.fetchKboAfternoon = onSchedule({
  schedule: "0 4,7,10,13 * * *",
  timeZone: "UTC",
  secrets: [apiSportsKey],
}, async (event) => {
  try {
    await syncKBO(apiSportsKey.value());
  } catch (err) {
    console.error("KBO 동기화 실패:", err.message || String(err));
  }
});

/** 시즌(3~11월) 경기 시간대: 5분마다 (라이브 스코어 Firestore 반영) */
exports.fetchKboGameTime = onSchedule({
  schedule: "*/5 5,6,7,8,9,10,11,12,13,14,15,16 * 3,4,5,6,7,8,9,10,11 *",
  timeZone: "UTC",
  secrets: [apiSportsKey],
}, async (event) => {
  try {
    await syncKBO(apiSportsKey.value());
  } catch (err) {
    console.error("KBO 동기화 실패:", err.message || String(err));
  }
});

/**
 * API-Sports에서 KBO 데이터를 가져와 Firestore에 동기화합니다.
 * @param {string} apiKey - API-Sports 시크릿 키
 */
async function syncKBO(apiKey) {
  const db = admin.firestore();

  // games와 standings를 병렬 요청 (API 할당량 2건 소모)
  const [gamesResp, standingsResp] = await Promise.all([
    axios.get(`${BASE_URL}/games`, {
      params: {league: KBO_LEAGUE_ID, season: KBO_SEASON},
      headers: {"x-apisports-key": apiKey},
      timeout: 15000,
    }),
    axios.get(`${BASE_URL}/standings`, {
      params: {league: KBO_LEAGUE_ID, season: KBO_SEASON},
      headers: {"x-apisports-key": apiKey},
      timeout: 15000,
    }),
  ]);

  const games = gamesResp.data.response;
  if (!games || games.length === 0) {
    console.warn("games 응답이 비어있습니다.");
    return;
  }

  const validGames = games.filter((g) => {
    return g && g.id && g.teams && g.teams.home && g.teams.away;
  });

  const slimGames = validGames.map((g) => {
    // API-Sports 실제 응답 구조: g.scores.home.innings["1"] ~ ["9"], .extra
    const hi = g.scores?.home?.innings;
    const ai = g.scores?.away?.innings;

    return {
      id: g.id,
      date: g.date,
      stage: g.stage || "Regular Season",
      status: {
        short: g.status?.short ?? "NS",
        long: g.status?.long ?? "",
      },
      teams: {
        home: {
          id: g.teams.home.id,
          name: g.teams.home.name,
          logo: g.teams.home.logo || null,
        },
        away: {
          id: g.teams.away.id,
          name: g.teams.away.name,
          logo: g.teams.away.logo || null,
        },
      },
      scores: {
        homeInnings: [
          hi?.["1"] ?? null,
          hi?.["2"] ?? null,
          hi?.["3"] ?? null,
          hi?.["4"] ?? null,
          hi?.["5"] ?? null,
          hi?.["6"] ?? null,
          hi?.["7"] ?? null,
          hi?.["8"] ?? null,
          hi?.["9"] ?? null,
          hi?.extra ?? null,
        ],
        awayInnings: [
          ai?.["1"] ?? null,
          ai?.["2"] ?? null,
          ai?.["3"] ?? null,
          ai?.["4"] ?? null,
          ai?.["5"] ?? null,
          ai?.["6"] ?? null,
          ai?.["7"] ?? null,
          ai?.["8"] ?? null,
          ai?.["9"] ?? null,
          ai?.extra ?? null,
        ],
        homeTotal: g.scores?.home?.total ?? null,
        awayTotal: g.scores?.away?.total ?? null,
      },
    };
  });

  // API-Sports 공식 순위 파싱
  const rawStandings = standingsResp.data.response?.[0] ?? [];
  const standings = rawStandings.map((s) => ({
    position: s.position,
    teamID: s.team.id,
    teamName: s.team.name,
    teamLogo: s.team.logo ?? null,
    gamesPlayed: s.games.played,
    wins: s.games.win.total,
    losses: s.games.lose.total,
    draws: s.games.draw?.total ?? 0,
    winPct: parseFloat(s.games.win.percentage),
    form: s.form ?? null,
    description: s.description ?? null,
  }));

  // 앱이 kbo_cache/meta만 먼저 읽어 games 문서(대용량) 다운로드를 건너뛸 수 있도록 동기화 토큰 부여
  const gamesSyncIso = new Date().toISOString();
  const liveShorts = new Set([
    "1ST", "2ND", "3RD", "4TH", "5TH", "6TH", "7TH", "8TH", "9TH",
    "LIVE", "IN_PLAY", "ET", "HT",
  ]);
  const hasLiveGame = slimGames.some((g) => {
    const s = (g.status && g.status.short) || "";
    if (liveShorts.has(s)) return true;
    if (/^IN\d+$/.test(s)) return true;
    const n = parseInt(s, 10);
    return !Number.isNaN(n) && n >= 1 && n <= 18;
  });

  // 지문: API 응답 순서 흔들림 방지를 위해 id 기준 정렬 후 SHA-256
  const syncPayload = JSON.stringify({
    g: [...slimGames].sort((a, b) => a.id - b.id).map((g) => ({
      id: g.id,
      s: g.status.short,
      h: g.scores.homeTotal,
      a: g.scores.awayTotal,
    })),
    s: [...standings].sort((a, b) => a.teamID - b.teamID).map((row) => ({
      id: row.teamID,
      p: row.position,
      w: row.wins,
      l: row.losses,
      d: row.draws,
    })),
  });
  const currentHash = crypto.createHash("sha256").update(syncPayload).digest("hex");

  const syncStateRef = db.collection("kbo_cache").doc("_sync_state");
  const syncStateDoc = await syncStateRef.get();
  const oldHash = syncStateDoc.exists ? (syncStateDoc.data().contentHash || "") : "";

  if (currentHash === oldHash && !hasLiveGame) {
    console.log(
      `KBO: [Skip] 변동 없음 (hash ${currentHash.slice(0, 8)}…). Firestore 쓰기 생략.`
    );
    return;
  }

  const batch = db.batch();

  batch.set(db.collection("kbo_cache").doc("meta"), {
    season: KBO_SEASON,
    leagueId: KBO_LEAGUE_ID,
    gamesSyncIso,
    gamesCount: slimGames.length,
    hasLiveGame,
    gamesLastUpdated: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  batch.set(db.collection("kbo_cache").doc("games"), {
    season: KBO_SEASON,
    leagueId: KBO_LEAGUE_ID,
    gamesSyncIso,
    lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    games: slimGames,
  });

  batch.set(db.collection("kbo_cache").doc("standings"), {
    season: KBO_SEASON,
    source: "api-sports",
    lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    standings: standings,
  });

  batch.set(syncStateRef, {
    contentHash: currentHash,
    checkedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await batch.commit();
  console.log(
    `KBO 동기화 완료: ${slimGames.length}경기, 순위 ${standings.length}팀 (hash ${currentHash.slice(0, 8)}…)`
  );
}

