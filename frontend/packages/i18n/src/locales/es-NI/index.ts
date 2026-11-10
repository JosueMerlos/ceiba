import { appointments } from "./appointments";
import { auth } from "./auth";
import { common } from "./common";
import { errors } from "./errors";
import { shell } from "./shell";

export const esNI = { common, auth, shell, errors, appointments } as const;
