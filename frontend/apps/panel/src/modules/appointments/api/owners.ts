import type { UseQueryResult } from "@tanstack/react-query";
import {
  useCreateProfessionalTimeOff,
  useDeleteProfessionalTimeOff,
  useProfessionalScheduleQuery,
  useProfessionalTimeOffsQuery,
  usePutProfessionalSchedule,
} from "./professionals";
import {
  useCreateResourceTimeOff,
  useDeleteResourceTimeOff,
  usePutResourceSchedule,
  useResourceScheduleQuery,
  useResourceTimeOffsQuery,
} from "./resources";
import type { TimeOff, TimeOffInput, WeeklyScheduleInput, WeeklyScheduleSlot } from "./shared";

export interface SaveSchedule {
  isPending: boolean;
  mutate(
    body: WeeklyScheduleInput,
    options: { onSuccess(): void; onError(error: unknown): void },
  ): void;
}

export interface CreateTimeOff {
  isPending: boolean;
  mutateAsync(values: TimeOffInput): Promise<unknown>;
}

export interface DeleteTimeOff {
  mutate(timeOffId: string, options: { onSuccess(): void }): void;
}

/**
 * The weekly hours and absences of an owner in one branch. Professionals and resources expose the same operations
 * on different endpoints; the screens that show or edit them take one of the instances below.
 */
export interface OwnerApi {
  useSchedule(
    branchId: string,
    ownerId: string,
    options?: { enabled?: boolean },
  ): UseQueryResult<{ data: WeeklyScheduleSlot[] }>;
  usePutSchedule(branchId: string, ownerId: string): SaveSchedule;
  useTimeOffs(
    branchId: string,
    ownerId: string,
    options?: { enabled?: boolean },
  ): UseQueryResult<{ data: TimeOff[] }>;
  useCreateTimeOff(branchId: string, ownerId: string): CreateTimeOff;
  useDeleteTimeOff(branchId: string, ownerId: string): DeleteTimeOff;
}

export const professionalOwnerApi: OwnerApi = {
  useSchedule: useProfessionalScheduleQuery,
  usePutSchedule: usePutProfessionalSchedule,
  useTimeOffs: useProfessionalTimeOffsQuery,
  useCreateTimeOff: useCreateProfessionalTimeOff,
  useDeleteTimeOff: useDeleteProfessionalTimeOff,
};

export const resourceOwnerApi: OwnerApi = {
  useSchedule: useResourceScheduleQuery,
  usePutSchedule: usePutResourceSchedule,
  useTimeOffs: useResourceTimeOffsQuery,
  useCreateTimeOff: useCreateResourceTimeOff,
  useDeleteTimeOff: useDeleteResourceTimeOff,
};

/**
 * The hours and absences of one owner in one branch, held by the modal: its footer offers a save only once the form
 * these seed is on screen. Each stays off until its section is.
 */
export function useOwnerReads(
  api: OwnerApi,
  branchId: string,
  ownerId: string,
  enabled: { schedule: boolean; timeOffs: boolean },
) {
  const schedule = api.useSchedule(branchId, ownerId, { enabled: enabled.schedule });
  const timeOffs = api.useTimeOffs(branchId, ownerId, { enabled: enabled.timeOffs });
  return { schedule, timeOffs };
}

export type OwnerReads = ReturnType<typeof useOwnerReads>;

/** The writes of one owner in one branch, held by the modal so its footer shows their progress. */
export function useOwnerWrites(api: OwnerApi, branchId: string, ownerId: string) {
  const saveSchedule = api.usePutSchedule(branchId, ownerId);
  const createTimeOff = api.useCreateTimeOff(branchId, ownerId);
  const deleteTimeOff = api.useDeleteTimeOff(branchId, ownerId);
  return {
    saveSchedule,
    createTimeOff,
    deleteTimeOff,
    /** What the footer's button is waiting on, per section. */
    pending: { schedule: saveSchedule.isPending, timeOffs: createTimeOff.isPending },
  };
}

export type OwnerWrites = ReturnType<typeof useOwnerWrites>;
