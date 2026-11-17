import type { BrandingFile } from "@ceiba/api-client";
import { FONT_CHOICES, FONT_FAMILIES, type FontChoice } from "@ceiba/branding";
import { useTranslation } from "@ceiba/i18n";
import {
  ColorField,
  FileDrop,
  FormControl,
  FormDescription,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
  Input,
  cn,
} from "@ceiba/ui";
import { useFormContext } from "react-hook-form";
import {
  COLOR_FIELDS,
  FILE_FIELDS,
  isValidColorInput,
  type BrandingFormValues,
} from "./branding-form";
import { loadBrandFont } from "./fonts";

const FILE_ACCEPT = "image/png,image/jpeg,image/webp";

interface BrandingEditPanelProps {
  previews: Record<BrandingFile, string | null>;
  onSelectFile: (name: BrandingFile, file: File) => void;
  onRemoveFile: (name: BrandingFile) => void;
}

/** Fields of the brand. It only renders inputs: state lives in the form and in `useBrandingFiles`. */
export function BrandingEditPanel({
  previews,
  onSelectFile,
  onRemoveFile,
}: BrandingEditPanelProps) {
  const { t } = useTranslation("branding");
  const form = useFormContext<BrandingFormValues>();

  return (
    <div className="grid gap-5">
      <FormField
        control={form.control}
        name="brandName"
        rules={{ maxLength: { value: 80, message: t("errors.tooLong") } }}
        render={({ field }) => (
          <FormItem>
            <FormLabel>{t("fields.brandName")}</FormLabel>
            <FormControl>
              <Input {...field} autoComplete="organization" />
            </FormControl>
            <FormMessage />
          </FormItem>
        )}
      />
      <FormField
        control={form.control}
        name="tagline"
        rules={{ maxLength: { value: 140, message: t("errors.tooLong") } }}
        render={({ field }) => (
          <FormItem>
            <FormLabel>{t("fields.tagline")}</FormLabel>
            <FormControl>
              <Input {...field} />
            </FormControl>
            <FormMessage />
          </FormItem>
        )}
      />

      {COLOR_FIELDS.map((name) => (
        <FormField
          key={name}
          control={form.control}
          name={name}
          rules={{ validate: (value) => isValidColorInput(value) || t("errors.invalidColor") }}
          render={({ field }) => (
            <FormItem>
              <FormLabel>{t(`fields.${name}`)}</FormLabel>
              <FormControl>
                <ColorField
                  name={field.name}
                  onBlur={field.onBlur}
                  ref={field.ref}
                  value={field.value}
                  onValueChange={field.onChange}
                  pickerLabel={t("fields.colorPicker", { name: t(`fields.${name}`).toLowerCase() })}
                  placeholder="#1D6C4E"
                />
              </FormControl>
              <FormDescription>{t("fields.colorHint")}</FormDescription>
              <FormMessage />
            </FormItem>
          )}
        />
      ))}

      <FormField
        control={form.control}
        name="fontChoice"
        render={({ field }) => (
          <fieldset className="grid gap-2" aria-describedby="branding-font-hint">
            <legend className="mb-2 text-sm leading-none font-medium">
              {t("fields.fontChoice")}
            </legend>
            <div className="grid gap-2">
              {FONT_CHOICES.map((choice) => (
                <FontOption
                  key={choice}
                  choice={choice}
                  checked={(field.value || "figtree") === choice}
                  onSelect={() => field.onChange(choice === "figtree" ? "" : choice)}
                />
              ))}
            </div>
            <p id="branding-font-hint" className="text-sm text-muted-foreground">
              {t("fields.fontHint")}
            </p>
          </fieldset>
        )}
      />

      {FILE_FIELDS.map((name) => (
        <FormField
          key={name}
          control={form.control}
          name={name}
          render={() => (
            <FormItem>
              <FormLabel>{t(`fields.${name}`)}</FormLabel>
              <FormControl>
                <FileDrop
                  accept={FILE_ACCEPT}
                  previewUrl={previews[name]}
                  previewAlt={t("files.previewAlt", { name: t(`fields.${name}`) })}
                  chooseLabel={t("files.choose")}
                  replaceLabel={t("files.replace")}
                  removeLabel={t("files.remove", { name: t(`fields.${name}`) })}
                  emptyLabel={t("files.empty")}
                  onSelect={(file) => {
                    form.clearErrors(name);
                    onSelectFile(name, file);
                  }}
                  onRemove={() => {
                    form.clearErrors(name);
                    onRemoveFile(name);
                  }}
                />
              </FormControl>
              <FormDescription>{t(`files.${name}Hint`)}</FormDescription>
              <FormMessage />
            </FormItem>
          )}
        />
      ))}
    </div>
  );
}

function FontOption({
  choice,
  checked,
  onSelect,
}: {
  choice: FontChoice;
  checked: boolean;
  onSelect: () => void;
}) {
  const { t } = useTranslation("branding");
  // The face is fetched when someone shows interest in it, so its own sample renders right.
  const preload = () => void loadBrandFont(choice);
  return (
    <label
      onPointerEnter={preload}
      className={cn(
        "flex cursor-pointer items-center gap-3 rounded-lg border bg-card px-3.5 py-2.5 transition-colors hover:bg-muted",
        "has-checked:border-primary has-checked:bg-accent has-focus-visible:outline-2 has-focus-visible:outline-offset-2 has-focus-visible:outline-ring",
      )}
    >
      <input
        type="radio"
        name="fontChoice"
        value={choice}
        checked={checked}
        onFocus={preload}
        onChange={() => {
          preload();
          onSelect();
        }}
        className="sr-only"
      />
      <span className="grid min-w-0">
        <span className="text-sm font-medium">{t(`fonts.${choice}`)}</span>
        <span className="truncate text-lg" style={{ fontFamily: FONT_FAMILIES[choice] }}>
          {t("fields.fontSample")}
        </span>
      </span>
    </label>
  );
}
