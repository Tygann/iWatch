import { decodeJwt, importPKCS8, SignJWT } from "npm:jose@6.1.3";

const appleURL = "https://appleid.apple.com";
const clientID = "com.tyler.iWatch";

function error(status: number, message: string): Response {
  return Response.json({ error: message }, { status });
}

async function revokeAppleAccess(
  code: string,
  subjects: string[],
  signing: { teamID: string; keyID: string; privateKey: string },
): Promise<boolean> {
  const key = await importPKCS8(signing.privateKey, "ES256");
  const clientSecret = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: signing.keyID })
    .setIssuer(signing.teamID)
    .setSubject(clientID)
    .setAudience(appleURL)
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(key);

  async function applePost(endpoint: string, parameters: Record<string, string>) {
    return await fetch(appleURL + endpoint, {
      method: "POST",
      body: new URLSearchParams({
        client_id: clientID,
        client_secret: clientSecret,
        ...parameters,
      }),
    });
  }

  const exchange = await applePost("/auth/token", {
    code,
    grant_type: "authorization_code",
  });
  if (!exchange.ok) return false;

  const tokens = await exchange.json();
  if (typeof tokens.id_token !== "string" ||
      typeof tokens.refresh_token !== "string") return false;

  // This token came directly from Apple's authenticated HTTPS token endpoint.
  const identity = decodeJwt(tokens.id_token);
  if (identity.iss !== appleURL || identity.aud !== clientID ||
      typeof identity.sub !== "string" || !subjects.includes(identity.sub)) {
    return false;
  }

  const revoked = await applePost("/auth/revoke", {
    token: tokens.refresh_token,
    token_type_hint: "refresh_token",
  });
  return revoked.ok;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return error(405, "Method not allowed");

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return error(401, "Sign-in required");

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return error(503, "Account deletion unavailable");

  try {
    const userResponse = await fetch(url + "/auth/v1/user", {
      headers: { apikey: serviceKey, Authorization: authorization },
    });
    if (!userResponse.ok) return error(401, "Sign-in required");

    const user: {
      id: string;
      identities?: { provider: string; identity_data?: { sub?: string } }[];
    } = await userResponse.json();
    if (!user.id) return error(401, "Sign-in required");

    const teamID = Deno.env.get("APPLE_TEAM_ID");
    const keyID = Deno.env.get("APPLE_KEY_ID");
    const privateKey = Deno.env.get("APPLE_PRIVATE_KEY");
    if (!teamID || !keyID || !privateKey) {
      return error(503, "Apple revocation is not configured");
    }

    const body = await request.json().catch(() => null);
    const code = body?.authorization_code;
    if (typeof code !== "string" || code.length === 0 || code.length > 4096) {
      return error(400, "Apple authorization code required");
    }
    const subjects = (user.identities ?? []).flatMap(({ provider, identity_data }) =>
      provider === "apple" && identity_data?.sub ? [identity_data.sub] : []
    );
    if (subjects.length === 0 ||
        !await revokeAppleAccess(code, subjects, { teamID, keyID, privateKey })) {
      return error(403, "Could not confirm the Apple account");
    }

    const deletion = await fetch(url + "/auth/v1/admin/users/" + encodeURIComponent(user.id), {
      method: "DELETE",
      headers: { apikey: serviceKey, Authorization: "Bearer " + serviceKey },
    });
    if (!deletion.ok && deletion.status !== 404) {
      return error(502, "Could not delete account");
    }
    return new Response(null, { status: 204 });
  } catch {
    return error(502, "Could not complete account deletion");
  }
});
