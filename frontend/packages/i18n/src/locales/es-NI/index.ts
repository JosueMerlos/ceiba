import { appointments } from "./appointments";
import { auth } from "./auth";
import { booking } from "./booking";
import { branding } from "./branding";
import { common } from "./common";
import { errors } from "./errors";
import { shell } from "./shell";

export const esNI = { common, auth, shell, errors, appointments, booking, branding } as const;
