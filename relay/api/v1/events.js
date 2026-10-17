import { waitUntil } from "@vercel/functions";
import { events } from "../../lib/relay.js";

export function POST(request) {
  return events(request, { waitUntil });
}
