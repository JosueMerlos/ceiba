import { useState, type Dispatch, type SetStateAction } from "react";

/**
 * The state of a creation modal in steps: the first step creates the record, the rest are optional and work on it.
 * Leaving a step (forward or back) forgets its unsaved state; moving past the last one finishes.
 */
export function useCreationSteps<Step extends string, Created>(
  steps: readonly Step[],
  onFinish: () => void,
) {
  const [step, setStep] = useState<Step>(steps[0]!);
  const [created, setCreated] = useState<Created | null>(null);
  const [dirty, setDirty] = useState(false);
  const index = steps.indexOf(step);

  const goTo = (target: Step | undefined) => {
    setDirty(false);
    if (target) setStep(target);
    else onFinish();
  };

  return {
    step,
    index,
    created,
    setCreated,
    dirty,
    setDirty,
    /** Continue must submit: the step has changes, or it is the first one and nothing exists yet. */
    mustSubmit: dirty || (index === 0 && created === null),
    next: () => goTo(steps[index + 1]),
    back: () => goTo(steps[index - 1]),
  };
}

interface CreationSteps<Created> {
  created: Created | null;
  setCreated: Dispatch<SetStateAction<Created | null>>;
  next(): void;
}

/**
 * The first step's save: creates the record the first time and updates it when the user comes back to change it,
 * never creating a second one. The modal only submits a step with changes, so an update always has something to send.
 */
export async function createOrUpdate<Created extends { id: string }>(
  flow: CreationSteps<Created>,
  requests: {
    create(): Promise<{ data: Created }>;
    update(id: string): Promise<{ data: Created }>;
  },
) {
  const result = flow.created ? await requests.update(flow.created.id) : await requests.create();
  flow.setCreated(result.data);
  flow.next();
  return result.data;
}
