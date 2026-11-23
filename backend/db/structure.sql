SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: btree_gist; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;


--
-- Name: EXTENSION btree_gist; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION btree_gist IS 'support for indexing common datatypes in GiST';


--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: reject_audit_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reject_audit_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION '% es append-only: % no está permitido', TG_TABLE_NAME, TG_OP USING ERRCODE = 'restrict_violation';
END
$$;


--
-- Name: reject_row_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reject_row_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION '% es inmutable: % no está permitido', TG_TABLE_NAME, TG_OP USING ERRCODE = 'restrict_violation';
END
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id uuid DEFAULT uuidv7() NOT NULL,
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    record_id uuid NOT NULL,
    blob_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id uuid DEFAULT uuidv7() NOT NULL,
    key character varying NOT NULL,
    filename character varying NOT NULL,
    content_type character varying,
    metadata text,
    service_name character varying NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id uuid DEFAULT uuidv7() NOT NULL,
    blob_id uuid NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: appointment_services; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.appointment_services (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    company_id uuid NOT NULL,
    appointment_id uuid NOT NULL,
    service_id uuid NOT NULL,
    "position" integer NOT NULL,
    duration_minutes integer NOT NULL,
    buffer_before_minutes integer NOT NULL,
    buffer_after_minutes integer NOT NULL,
    price_minor bigint NOT NULL,
    currency character varying(3) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_appointment_services_buffers CHECK (((buffer_before_minutes >= 0) AND (buffer_after_minutes >= 0))),
    CONSTRAINT chk_appointment_services_currency CHECK (((currency)::text ~ '^[A-Z]{3}$'::text)),
    CONSTRAINT chk_appointment_services_duration CHECK ((duration_minutes > 0)),
    CONSTRAINT chk_appointment_services_position CHECK (("position" >= 0)),
    CONSTRAINT chk_appointment_services_price CHECK ((price_minor >= 0))
);


--
-- Name: appointments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.appointments (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    company_id uuid NOT NULL,
    branch_id uuid NOT NULL,
    professional_id uuid NOT NULL,
    resource_id uuid,
    starts_at timestamp(6) without time zone NOT NULL,
    ends_at timestamp(6) without time zone NOT NULL,
    blocks_from timestamp(6) without time zone NOT NULL,
    blocks_to timestamp(6) without time zone NOT NULL,
    status character varying DEFAULT 'scheduled'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    customer_id uuid NOT NULL,
    source character varying NOT NULL,
    notes text,
    lock_version integer DEFAULT 0 NOT NULL,
    created_by_type character varying NOT NULL,
    created_by_id uuid,
    rescheduled_from_id uuid,
    cancelled_by character varying,
    cancellation_reason character varying,
    CONSTRAINT chk_appointments_cancellation CHECK (((((status)::text <> 'cancelled'::text) AND (cancelled_by IS NULL) AND (cancellation_reason IS NULL)) OR (((status)::text = 'cancelled'::text) AND (cancelled_by IS NOT NULL) AND (cancellation_reason IS NOT NULL)))),
    CONSTRAINT chk_appointments_cancellation_reason CHECK (((cancellation_reason IS NULL) OR ((cancellation_reason)::text = 'customer_request'::text) OR ((cancellation_reason)::text = 'professional_unavailable'::text) OR ((cancellation_reason)::text = 'business_decision'::text) OR ((cancellation_reason)::text = 'other'::text))),
    CONSTRAINT chk_appointments_cancelled_by CHECK (((cancelled_by IS NULL) OR ((cancelled_by)::text = 'staff'::text) OR ((cancelled_by)::text = 'customer'::text) OR ((cancelled_by)::text = 'system'::text))),
    CONSTRAINT chk_appointments_created_by_type CHECK ((((created_by_type)::text = 'user'::text) OR ((created_by_type)::text = 'api_key'::text) OR ((created_by_type)::text = 'system'::text) OR ((created_by_type)::text = 'public_token'::text) OR ((created_by_type)::text = 'platform_staff'::text))),
    CONSTRAINT chk_appointments_created_by_user_id CHECK ((((created_by_type)::text <> 'user'::text) OR (created_by_id IS NOT NULL))),
    CONSTRAINT chk_appointments_source CHECK ((((source)::text = 'panel'::text) OR ((source)::text = 'public_booking'::text))),
    CONSTRAINT chk_appointments_status CHECK ((((status)::text = 'scheduled'::text) OR ((status)::text = 'confirmed'::text) OR ((status)::text = 'checked_in'::text) OR ((status)::text = 'completed'::text) OR ((status)::text = 'cancelled'::text) OR ((status)::text = 'rescheduled'::text) OR ((status)::text = 'no_show'::text))),
    CONSTRAINT chk_appointments_valid_interval CHECK (((starts_at < ends_at) AND (blocks_from <= starts_at) AND (blocks_to >= ends_at)))
);


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: audit_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_events (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    actor_type character varying NOT NULL,
    actor_id uuid,
    request_id character varying,
    ip inet,
    user_agent character varying,
    action character varying NOT NULL,
    auditable_type character varying NOT NULL,
    auditable_id uuid NOT NULL,
    before jsonb,
    after jsonb,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: auth_audit_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_audit_events (
    id uuid DEFAULT uuidv7() NOT NULL,
    action character varying NOT NULL,
    user_id uuid,
    request_id character varying,
    ip inet,
    user_agent character varying,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: branch_module_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.branch_module_settings (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    company_id uuid NOT NULL,
    branch_id uuid NOT NULL,
    module_key character varying NOT NULL,
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_branch_module_settings_settings_object CHECK ((jsonb_typeof(settings) = 'object'::text)),
    CONSTRAINT chk_branch_module_settings_settings_size CHECK ((pg_column_size(settings) < 16384))
);


--
-- Name: branch_service_overrides; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.branch_service_overrides (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    company_id uuid NOT NULL,
    branch_id uuid NOT NULL,
    service_id uuid NOT NULL,
    duration_minutes integer,
    price_minor bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_bso_duration_positive CHECK ((duration_minutes > 0)),
    CONSTRAINT chk_bso_overrides_something CHECK (((duration_minutes IS NOT NULL) OR (price_minor IS NOT NULL))),
    CONSTRAINT chk_bso_price_non_negative CHECK ((price_minor >= 0))
);


--
-- Name: branches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.branches (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    company_id uuid NOT NULL,
    name character varying NOT NULL,
    time_zone character varying DEFAULT 'America/Managua'::character varying NOT NULL,
    address character varying,
    phone_e164 character varying,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_branches_phone_e164 CHECK (((phone_e164 IS NULL) OR ((phone_e164)::text ~ '^\+[1-9][0-9]{6,14}$'::text))),
    CONSTRAINT chk_branches_status CHECK ((((status)::text = 'active'::text) OR ((status)::text = 'inactive'::text)))
);


--
-- Name: companies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.companies (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    name character varying NOT NULL,
    slug character varying NOT NULL,
    business_type character varying NOT NULL,
    currency character varying(3) NOT NULL,
    locale character varying DEFAULT 'es-NI'::character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    brand_name character varying(80),
    tagline character varying(140),
    primary_color character varying(7),
    secondary_color character varying(7),
    accent_color character varying(7),
    font_choice character varying,
    CONSTRAINT chk_companies_accent_color_format CHECK (((accent_color IS NULL) OR ((accent_color)::text ~ '^#[0-9A-F]{6}$'::text))),
    CONSTRAINT chk_companies_currency CHECK ((((currency)::text = 'NIO'::text) OR ((currency)::text = 'USD'::text))),
    CONSTRAINT chk_companies_font_choice CHECK (((font_choice IS NULL) OR ((font_choice)::text = 'figtree'::text) OR ((font_choice)::text = 'lora'::text) OR ((font_choice)::text = 'nunito'::text))),
    CONSTRAINT chk_companies_primary_color_format CHECK (((primary_color IS NULL) OR ((primary_color)::text ~ '^#[0-9A-F]{6}$'::text))),
    CONSTRAINT chk_companies_secondary_color_format CHECK (((secondary_color IS NULL) OR ((secondary_color)::text ~ '^#[0-9A-F]{6}$'::text))),
    CONSTRAINT chk_companies_slug_format CHECK (((slug)::text ~ '^[a-z0-9-]{3,40}$'::text)),
    CONSTRAINT chk_companies_status CHECK ((((status)::text = 'active'::text) OR ((status)::text = 'inactive'::text)))
);


--
-- Name: company_modules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.company_modules (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    company_id uuid NOT NULL,
    module_key character varying NOT NULL,
    enabled_at timestamp(6) without time zone NOT NULL,
    disabled_at timestamp(6) without time zone,
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_company_modules_module_key CHECK (((module_key)::text ~ '^[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT chk_company_modules_settings_object CHECK ((jsonb_typeof(settings) = 'object'::text)),
    CONSTRAINT chk_company_modules_settings_size CHECK ((pg_column_size(settings) < 16384))
);


--
-- Name: customers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customers (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    company_id uuid NOT NULL,
    full_name character varying NOT NULL,
    phone_e164 character varying NOT NULL,
    email character varying,
    notes text,
    archived_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_customers_full_name_present CHECK ((length(btrim((full_name)::text)) > 0))
);


--
-- Name: flipper_features; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.flipper_features (
    id uuid DEFAULT uuidv7() NOT NULL,
    key character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: flipper_gates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.flipper_gates (
    id uuid DEFAULT uuidv7() NOT NULL,
    feature_key character varying NOT NULL,
    key character varying NOT NULL,
    value text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: idempotency_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.idempotency_keys (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    principal_key character varying NOT NULL,
    key character varying NOT NULL,
    request_fingerprint character varying NOT NULL,
    response_status integer,
    response_body text,
    response_headers jsonb DEFAULT '{}'::jsonb NOT NULL,
    content_type character varying,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: import_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.import_batches (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    company_id uuid NOT NULL,
    branch_id uuid NOT NULL,
    kind character varying NOT NULL,
    status character varying DEFAULT 'previewed'::character varying NOT NULL,
    duplicate_mode character varying,
    created_by_id uuid NOT NULL,
    warnings jsonb DEFAULT '[]'::jsonb NOT NULL,
    total_count integer DEFAULT 0 NOT NULL,
    ready_count integer DEFAULT 0 NOT NULL,
    rejected_count integer DEFAULT 0 NOT NULL,
    created_count integer DEFAULT 0 NOT NULL,
    updated_count integer DEFAULT 0 NOT NULL,
    restored_count integer DEFAULT 0 NOT NULL,
    skipped_count integer DEFAULT 0 NOT NULL,
    failed_count integer DEFAULT 0 NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    confirmed_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_import_batches_duplicate_mode CHECK (((duplicate_mode IS NULL) OR ((duplicate_mode)::text = ANY ((ARRAY['skip'::character varying, 'update'::character varying])::text[])))),
    CONSTRAINT chk_import_batches_kind CHECK (((kind)::text = ANY ((ARRAY['customers'::character varying, 'services'::character varying, 'professionals'::character varying])::text[]))),
    CONSTRAINT chk_import_batches_status CHECK (((status)::text = ANY ((ARRAY['previewed'::character varying, 'queued'::character varying, 'processing'::character varying, 'completed'::character varying, 'failed'::character varying, 'expired'::character varying])::text[])))
);


--
-- Name: import_rows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.import_rows (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    import_batch_id uuid NOT NULL,
    row_number integer NOT NULL,
    status character varying NOT NULL,
    payload text,
    error_codes jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_import_rows_row_number_positive CHECK ((row_number > 0)),
    CONSTRAINT chk_import_rows_status CHECK (((status)::text = ANY ((ARRAY['ready'::character varying, 'rejected'::character varying, 'created'::character varying, 'updated'::character varying, 'restored'::character varying, 'skipped'::character varying, 'failed'::character varying])::text[])))
);


--
-- Name: memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.memberships (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role_id uuid NOT NULL,
    scope_level character varying NOT NULL,
    company_id uuid,
    branch_id uuid,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_memberships_scope CHECK (((((scope_level)::text = 'organization'::text) AND (company_id IS NULL) AND (branch_id IS NULL)) OR (((scope_level)::text = 'company'::text) AND (company_id IS NOT NULL) AND (branch_id IS NULL)) OR (((scope_level)::text = 'branch'::text) AND (company_id IS NOT NULL) AND (branch_id IS NOT NULL))))
);


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    id uuid DEFAULT uuidv7() NOT NULL,
    name character varying NOT NULL,
    legal_name character varying,
    country_code character varying(2) DEFAULT 'NI'::character varying NOT NULL,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_organizations_country_code CHECK (((country_code)::text ~ '^[A-Z]{2}$'::text)),
    CONSTRAINT chk_organizations_status CHECK ((((status)::text = 'active'::text) OR ((status)::text = 'suspended'::text)))
);


--
-- Name: outbox_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.outbox_events (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    name character varying NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    occurred_at timestamp(6) without time zone NOT NULL,
    published_at timestamp(6) without time zone,
    attempts integer DEFAULT 0 NOT NULL,
    last_error text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_outbox_events_name_format CHECK (((name)::text ~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\.v[0-9]+$'::text))
);


--
-- Name: permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.permissions (
    key character varying NOT NULL,
    module_key character varying NOT NULL,
    description character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_permissions_key_format CHECK (((key)::text ~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$'::text)),
    CONSTRAINT chk_permissions_module_prefix CHECK ((split_part((key)::text, '.'::text, 1) = (module_key)::text))
);


--
-- Name: processed_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.processed_events (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    subscriber character varying NOT NULL,
    processed_at timestamp(6) without time zone DEFAULT now() NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: professional_branch_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.professional_branch_assignments (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    company_id uuid NOT NULL,
    professional_id uuid NOT NULL,
    branch_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: professional_services; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.professional_services (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    company_id uuid NOT NULL,
    professional_id uuid NOT NULL,
    service_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: professionals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.professionals (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    company_id uuid NOT NULL,
    user_id uuid,
    display_name character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    archived_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_professionals_name_present CHECK ((length(btrim((display_name)::text)) > 0))
);


--
-- Name: resources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.resources (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    company_id uuid NOT NULL,
    branch_id uuid NOT NULL,
    name character varying NOT NULL,
    kind character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    archived_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_resources_kind CHECK ((((kind)::text = 'chair'::text) OR ((kind)::text = 'room'::text) OR ((kind)::text = 'equipment'::text))),
    CONSTRAINT chk_resources_name_present CHECK ((length(btrim((name)::text)) > 0))
);


--
-- Name: role_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role_permissions (
    role_id uuid NOT NULL,
    permission_key character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roles (
    id uuid DEFAULT uuidv7() NOT NULL,
    key character varying NOT NULL,
    scope_level character varying NOT NULL,
    system boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_roles_scope_level CHECK ((((scope_level)::text = 'organization'::text) OR ((scope_level)::text = 'company'::text) OR ((scope_level)::text = 'branch'::text)))
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: service_resource_requirements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.service_resource_requirements (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    company_id uuid NOT NULL,
    service_id uuid NOT NULL,
    kind character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_srr_kind CHECK ((((kind)::text = 'chair'::text) OR ((kind)::text = 'room'::text) OR ((kind)::text = 'equipment'::text)))
);


--
-- Name: services; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.services (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    company_id uuid NOT NULL,
    name character varying NOT NULL,
    duration_minutes integer NOT NULL,
    buffer_before_minutes integer DEFAULT 0 NOT NULL,
    buffer_after_minutes integer DEFAULT 0 NOT NULL,
    price_minor bigint NOT NULL,
    currency character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    archived_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_services_buffer_after CHECK ((buffer_after_minutes >= 0)),
    CONSTRAINT chk_services_buffer_before CHECK ((buffer_before_minutes >= 0)),
    CONSTRAINT chk_services_currency CHECK ((((currency)::text = 'NIO'::text) OR ((currency)::text = 'USD'::text))),
    CONSTRAINT chk_services_duration_positive CHECK ((duration_minutes > 0)),
    CONSTRAINT chk_services_name_present CHECK ((length(btrim((name)::text)) > 0)),
    CONSTRAINT chk_services_price_non_negative CHECK ((price_minor >= 0))
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id uuid DEFAULT uuidv7() NOT NULL,
    user_id uuid NOT NULL,
    token_digest character varying NOT NULL,
    ip inet,
    user_agent character varying,
    last_seen_at timestamp(6) without time zone NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    revoked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: time_offs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.time_offs (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    company_id uuid NOT NULL,
    owner_type character varying NOT NULL,
    professional_id uuid,
    resource_id uuid,
    starts_at timestamp(6) without time zone NOT NULL,
    ends_at timestamp(6) without time zone NOT NULL,
    reason character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_time_offs_owner CHECK (((((owner_type)::text = 'professional'::text) AND (professional_id IS NOT NULL) AND (resource_id IS NULL)) OR (((owner_type)::text = 'resource'::text) AND (professional_id IS NULL) AND (resource_id IS NOT NULL)))),
    CONSTRAINT chk_time_offs_range CHECK ((starts_at < ends_at)),
    CONSTRAINT chk_time_offs_reason CHECK (((reason IS NULL) OR (char_length((reason)::text) <= 200)))
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT uuidv7() NOT NULL,
    email public.citext NOT NULL,
    password_digest character varying NOT NULL,
    full_name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: weekly_schedules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.weekly_schedules (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    company_id uuid NOT NULL,
    branch_id uuid NOT NULL,
    owner_type character varying NOT NULL,
    professional_id uuid,
    resource_id uuid,
    weekday smallint NOT NULL,
    starts_at_local time without time zone NOT NULL,
    ends_at_local time without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT chk_ws_minute_precision CHECK (((date_trunc('minute'::text, (starts_at_local)::interval) = (starts_at_local)::interval) AND (date_trunc('minute'::text, (ends_at_local)::interval) = (ends_at_local)::interval))),
    CONSTRAINT chk_ws_owner CHECK (((((owner_type)::text = 'branch'::text) AND (professional_id IS NULL) AND (resource_id IS NULL)) OR (((owner_type)::text = 'professional'::text) AND (professional_id IS NOT NULL) AND (resource_id IS NULL)) OR (((owner_type)::text = 'resource'::text) AND (professional_id IS NULL) AND (resource_id IS NOT NULL)))),
    CONSTRAINT chk_ws_owner_type CHECK ((((owner_type)::text = 'branch'::text) OR ((owner_type)::text = 'professional'::text) OR ((owner_type)::text = 'resource'::text))),
    CONSTRAINT chk_ws_range CHECK ((starts_at_local < ends_at_local)),
    CONSTRAINT chk_ws_weekday CHECK (((weekday >= 0) AND (weekday <= 6)))
);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: appointment_services appointment_services_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointment_services
    ADD CONSTRAINT appointment_services_pkey PRIMARY KEY (id);


--
-- Name: appointments appointments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: audit_events audit_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_events
    ADD CONSTRAINT audit_events_pkey PRIMARY KEY (id);


--
-- Name: auth_audit_events auth_audit_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_audit_events
    ADD CONSTRAINT auth_audit_events_pkey PRIMARY KEY (id);


--
-- Name: branch_module_settings branch_module_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branch_module_settings
    ADD CONSTRAINT branch_module_settings_pkey PRIMARY KEY (id);


--
-- Name: branch_service_overrides branch_service_overrides_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branch_service_overrides
    ADD CONSTRAINT branch_service_overrides_pkey PRIMARY KEY (id);


--
-- Name: branches branches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT branches_pkey PRIMARY KEY (id);


--
-- Name: companies companies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT companies_pkey PRIMARY KEY (id);


--
-- Name: company_modules company_modules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_modules
    ADD CONSTRAINT company_modules_pkey PRIMARY KEY (id);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- Name: weekly_schedules ex_ws_branch; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_schedules
    ADD CONSTRAINT ex_ws_branch EXCLUDE USING gist (branch_id WITH =, weekday WITH =, int4range((((EXTRACT(hour FROM starts_at_local) * (60)::numeric) + EXTRACT(minute FROM starts_at_local)))::integer, (((EXTRACT(hour FROM ends_at_local) * (60)::numeric) + EXTRACT(minute FROM ends_at_local)))::integer, '[)'::text) WITH &&) WHERE (((owner_type)::text = 'branch'::text));


--
-- Name: weekly_schedules ex_ws_professional; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_schedules
    ADD CONSTRAINT ex_ws_professional EXCLUDE USING gist (professional_id WITH =, weekday WITH =, int4range((((EXTRACT(hour FROM starts_at_local) * (60)::numeric) + EXTRACT(minute FROM starts_at_local)))::integer, (((EXTRACT(hour FROM ends_at_local) * (60)::numeric) + EXTRACT(minute FROM ends_at_local)))::integer, '[)'::text) WITH &&) WHERE ((professional_id IS NOT NULL));


--
-- Name: weekly_schedules ex_ws_resource; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_schedules
    ADD CONSTRAINT ex_ws_resource EXCLUDE USING gist (resource_id WITH =, weekday WITH =, int4range((((EXTRACT(hour FROM starts_at_local) * (60)::numeric) + EXTRACT(minute FROM starts_at_local)))::integer, (((EXTRACT(hour FROM ends_at_local) * (60)::numeric) + EXTRACT(minute FROM ends_at_local)))::integer, '[)'::text) WITH &&) WHERE ((resource_id IS NOT NULL));


--
-- Name: flipper_features flipper_features_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flipper_features
    ADD CONSTRAINT flipper_features_pkey PRIMARY KEY (id);


--
-- Name: flipper_gates flipper_gates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flipper_gates
    ADD CONSTRAINT flipper_gates_pkey PRIMARY KEY (id);


--
-- Name: idempotency_keys idempotency_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idempotency_keys
    ADD CONSTRAINT idempotency_keys_pkey PRIMARY KEY (id);


--
-- Name: import_batches import_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_batches
    ADD CONSTRAINT import_batches_pkey PRIMARY KEY (id);


--
-- Name: import_rows import_rows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_rows
    ADD CONSTRAINT import_rows_pkey PRIMARY KEY (id);


--
-- Name: memberships memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT memberships_pkey PRIMARY KEY (id);


--
-- Name: appointments no_overlap_professional; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT no_overlap_professional EXCLUDE USING gist (professional_id WITH =, tsrange(blocks_from, blocks_to, '[)'::text) WITH &&) WHERE ((((status)::text <> 'cancelled'::text) AND ((status)::text <> 'rescheduled'::text)));


--
-- Name: appointments no_overlap_resource; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT no_overlap_resource EXCLUDE USING gist (resource_id WITH =, tsrange(blocks_from, blocks_to, '[)'::text) WITH &&) WHERE (((resource_id IS NOT NULL) AND ((status)::text <> 'cancelled'::text) AND ((status)::text <> 'rescheduled'::text)));


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: outbox_events outbox_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbox_events
    ADD CONSTRAINT outbox_events_pkey PRIMARY KEY (id);


--
-- Name: permissions permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_pkey PRIMARY KEY (key);


--
-- Name: processed_events processed_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processed_events
    ADD CONSTRAINT processed_events_pkey PRIMARY KEY (id);


--
-- Name: professional_branch_assignments professional_branch_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.professional_branch_assignments
    ADD CONSTRAINT professional_branch_assignments_pkey PRIMARY KEY (id);


--
-- Name: professional_services professional_services_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.professional_services
    ADD CONSTRAINT professional_services_pkey PRIMARY KEY (id);


--
-- Name: professionals professionals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.professionals
    ADD CONSTRAINT professionals_pkey PRIMARY KEY (id);


--
-- Name: resources resources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resources
    ADD CONSTRAINT resources_pkey PRIMARY KEY (id);


--
-- Name: role_permissions role_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (role_id, permission_key);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: service_resource_requirements service_resource_requirements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_resource_requirements
    ADD CONSTRAINT service_resource_requirements_pkey PRIMARY KEY (id);


--
-- Name: services services_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.services
    ADD CONSTRAINT services_pkey PRIMARY KEY (id);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: time_offs time_offs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_offs
    ADD CONSTRAINT time_offs_pkey PRIMARY KEY (id);


--
-- Name: appointment_services uq_appointment_services_organization_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointment_services
    ADD CONSTRAINT uq_appointment_services_organization_id_id UNIQUE (organization_id, id);


--
-- Name: appointments uq_appointments_org_company_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT uq_appointments_org_company_id UNIQUE (organization_id, company_id, id);


--
-- Name: appointments uq_appointments_organization_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT uq_appointments_organization_id_id UNIQUE (organization_id, id);


--
-- Name: audit_events uq_audit_events_organization_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_events
    ADD CONSTRAINT uq_audit_events_organization_id_id UNIQUE (organization_id, id);


--
-- Name: branch_module_settings uq_branch_module_settings_branch_module; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branch_module_settings
    ADD CONSTRAINT uq_branch_module_settings_branch_module UNIQUE (organization_id, branch_id, module_key);


--
-- Name: branch_module_settings uq_branch_module_settings_organization_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branch_module_settings
    ADD CONSTRAINT uq_branch_module_settings_organization_id_id UNIQUE (organization_id, id);


--
-- Name: branch_service_overrides uq_branch_service_overrides_organization_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branch_service_overrides
    ADD CONSTRAINT uq_branch_service_overrides_organization_id_id UNIQUE (organization_id, id);


--
-- Name: branches uq_branches_organization_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT uq_branches_organization_id_id UNIQUE (organization_id, id);


--
-- Name: companies uq_companies_organization_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT uq_companies_organization_id_id UNIQUE (organization_id, id);


--
-- Name: company_modules uq_company_modules_company_module; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_modules
    ADD CONSTRAINT uq_company_modules_company_module UNIQUE (organization_id, company_id, module_key);


--
-- Name: company_modules uq_company_modules_organization_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_modules
    ADD CONSTRAINT uq_company_modules_organization_id_id UNIQUE (organization_id, id);


--
-- Name: customers uq_customers_organization_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT uq_customers_organization_id_id UNIQUE (organization_id, id);


--
-- Name: idempotency_keys uq_idempotency_keys_organization_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idempotency_keys
    ADD CONSTRAINT uq_idempotency_keys_organization_id_id UNIQUE (organization_id, id);


--
-- Name: import_batches uq_import_batches_organization_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_batches
    ADD CONSTRAINT uq_import_batches_organization_id_id UNIQUE (organization_id, id);


--
-- Name: import_rows uq_import_rows_organization_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_rows
    ADD CONSTRAINT uq_import_rows_organization_id_id UNIQUE (organization_id, id);


--
-- Name: memberships uq_memberships_organization_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT uq_memberships_organization_id_id UNIQUE (organization_id, id);


--
-- Name: outbox_events uq_outbox_events_organization_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbox_events
    ADD CONSTRAINT uq_outbox_events_organization_id_id UNIQUE (organization_id, id);


--
-- Name: processed_events uq_processed_events_organization_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processed_events
    ADD CONSTRAINT uq_processed_events_organization_id_id UNIQUE (organization_id, id);


--
-- Name: professional_branch_assignments uq_professional_branch_assignments_organization_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.professional_branch_assignments
    ADD CONSTRAINT uq_professional_branch_assignments_organization_id_id UNIQUE (organization_id, id);


--
-- Name: professional_services uq_professional_services_organization_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.professional_services
    ADD CONSTRAINT uq_professional_services_organization_id_id UNIQUE (organization_id, id);


--
-- Name: professionals uq_professionals_organization_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.professionals
    ADD CONSTRAINT uq_professionals_organization_id_id UNIQUE (organization_id, id);


--
-- Name: resources uq_resources_organization_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resources
    ADD CONSTRAINT uq_resources_organization_id_id UNIQUE (organization_id, id);


--
-- Name: service_resource_requirements uq_service_resource_requirements_organization_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_resource_requirements
    ADD CONSTRAINT uq_service_resource_requirements_organization_id_id UNIQUE (organization_id, id);


--
-- Name: services uq_services_organization_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.services
    ADD CONSTRAINT uq_services_organization_id_id UNIQUE (organization_id, id);


--
-- Name: time_offs uq_time_offs_organization_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_offs
    ADD CONSTRAINT uq_time_offs_organization_id_id UNIQUE (organization_id, id);


--
-- Name: weekly_schedules uq_weekly_schedules_organization_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_schedules
    ADD CONSTRAINT uq_weekly_schedules_organization_id_id UNIQUE (organization_id, id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: weekly_schedules weekly_schedules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_schedules
    ADD CONSTRAINT weekly_schedules_pkey PRIMARY KEY (id);


--
-- Name: idx_appointment_services_service; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appointment_services_service ON public.appointment_services USING btree (organization_id, company_id, service_id);


--
-- Name: idx_appointments_branch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appointments_branch ON public.appointments USING btree (organization_id, company_id, branch_id);


--
-- Name: idx_appointments_branch_starts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appointments_branch_starts ON public.appointments USING btree (organization_id, branch_id, starts_at);


--
-- Name: idx_appointments_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appointments_customer ON public.appointments USING btree (organization_id, company_id, customer_id);


--
-- Name: idx_appointments_professional; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appointments_professional ON public.appointments USING btree (organization_id, company_id, professional_id);


--
-- Name: idx_appointments_professional_blocks; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appointments_professional_blocks ON public.appointments USING btree (organization_id, professional_id, blocks_to) WHERE (((status)::text <> 'cancelled'::text) AND ((status)::text <> 'rescheduled'::text));


--
-- Name: idx_appointments_professional_starts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appointments_professional_starts ON public.appointments USING btree (organization_id, professional_id, starts_at);


--
-- Name: idx_appointments_rescheduled_from; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appointments_rescheduled_from ON public.appointments USING btree (organization_id, company_id, rescheduled_from_id) WHERE (rescheduled_from_id IS NOT NULL);


--
-- Name: idx_appointments_resource; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appointments_resource ON public.appointments USING btree (organization_id, branch_id, resource_id) WHERE (resource_id IS NOT NULL);


--
-- Name: idx_appointments_resource_blocks; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_appointments_resource_blocks ON public.appointments USING btree (organization_id, resource_id, blocks_to) WHERE ((resource_id IS NOT NULL) AND ((status)::text <> 'cancelled'::text) AND ((status)::text <> 'rescheduled'::text));


--
-- Name: idx_audit_events_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_events_created_at ON public.audit_events USING btree (organization_id, created_at);


--
-- Name: idx_audit_events_subject; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_events_subject ON public.audit_events USING btree (organization_id, auditable_type, auditable_id);


--
-- Name: idx_auth_audit_events_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auth_audit_events_created_at ON public.auth_audit_events USING btree (created_at);


--
-- Name: idx_auth_audit_events_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auth_audit_events_user ON public.auth_audit_events USING btree (user_id, created_at);


--
-- Name: idx_bso_service; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bso_service ON public.branch_service_overrides USING btree (organization_id, company_id, service_id);


--
-- Name: idx_company_modules_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_company_modules_active ON public.company_modules USING btree (organization_id, module_key, company_id) WHERE (disabled_at IS NULL);


--
-- Name: idx_customers_company_active_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_company_active_id ON public.customers USING btree (organization_id, company_id, id) WHERE (archived_at IS NULL);


--
-- Name: idx_customers_company_name_prefix; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_company_name_prefix ON public.customers USING btree (organization_id, company_id, lower((full_name)::text) text_pattern_ops);


--
-- Name: idx_idempotency_keys_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_idempotency_keys_expires_at ON public.idempotency_keys USING btree (expires_at);


--
-- Name: idx_import_batches_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_import_batches_company_id ON public.import_batches USING btree (organization_id, company_id, id);


--
-- Name: idx_import_batches_status_expires; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_import_batches_status_expires ON public.import_batches USING btree (status, expires_at);


--
-- Name: idx_outbox_events_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_outbox_events_pending ON public.outbox_events USING btree (id) WHERE (published_at IS NULL);


--
-- Name: idx_outbox_events_published_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_outbox_events_published_at ON public.outbox_events USING btree (published_at) WHERE (published_at IS NOT NULL);


--
-- Name: idx_pba_branch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pba_branch ON public.professional_branch_assignments USING btree (organization_id, company_id, branch_id);


--
-- Name: idx_processed_events_processed_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_processed_events_processed_at ON public.processed_events USING btree (processed_at);


--
-- Name: idx_professionals_company_unarchived_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_professionals_company_unarchived_id ON public.professionals USING btree (organization_id, company_id, id) WHERE (archived_at IS NULL);


--
-- Name: idx_professionals_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_professionals_user ON public.professionals USING btree (user_id) WHERE (user_id IS NOT NULL);


--
-- Name: idx_ps_service; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ps_service ON public.professional_services USING btree (organization_id, company_id, service_id);


--
-- Name: idx_resources_branch_unarchived_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_resources_branch_unarchived_id ON public.resources USING btree (organization_id, branch_id, id) WHERE (archived_at IS NULL);


--
-- Name: idx_services_company_unarchived_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_services_company_unarchived_id ON public.services USING btree (organization_id, company_id, id) WHERE (archived_at IS NULL);


--
-- Name: idx_srr_service; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_srr_service ON public.service_resource_requirements USING btree (organization_id, company_id, service_id);


--
-- Name: idx_time_offs_professional_ends; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_time_offs_professional_ends ON public.time_offs USING btree (organization_id, professional_id, ends_at) WHERE (professional_id IS NOT NULL);


--
-- Name: idx_time_offs_resource_ends; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_time_offs_resource_ends ON public.time_offs USING btree (organization_id, resource_id, ends_at) WHERE (resource_id IS NOT NULL);


--
-- Name: idx_ws_branch_weekday; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ws_branch_weekday ON public.weekly_schedules USING btree (organization_id, branch_id, weekday);


--
-- Name: idx_ws_professional_branch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ws_professional_branch ON public.weekly_schedules USING btree (professional_id, branch_id) WHERE (professional_id IS NOT NULL);


--
-- Name: idx_ws_resource_branch; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ws_resource_branch ON public.weekly_schedules USING btree (resource_id, branch_id) WHERE (resource_id IS NOT NULL);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_branch_module_settings_on_organization_id_and_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_branch_module_settings_on_organization_id_and_company_id ON public.branch_module_settings USING btree (organization_id, company_id);


--
-- Name: index_branches_on_organization_id_and_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_branches_on_organization_id_and_company_id ON public.branches USING btree (organization_id, company_id);


--
-- Name: index_company_modules_on_organization_id_and_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_company_modules_on_organization_id_and_company_id ON public.company_modules USING btree (organization_id, company_id);


--
-- Name: index_flipper_features_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_flipper_features_on_key ON public.flipper_features USING btree (key);


--
-- Name: index_flipper_gates_on_feature_key_and_key_and_value; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_flipper_gates_on_feature_key_and_key_and_value ON public.flipper_gates USING btree (feature_key, key, value);


--
-- Name: index_memberships_on_organization_id_and_branch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memberships_on_organization_id_and_branch_id ON public.memberships USING btree (organization_id, branch_id);


--
-- Name: index_memberships_on_organization_id_and_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memberships_on_organization_id_and_company_id ON public.memberships USING btree (organization_id, company_id);


--
-- Name: index_memberships_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memberships_on_user_id ON public.memberships USING btree (user_id);


--
-- Name: index_permissions_on_module_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_permissions_on_module_key ON public.permissions USING btree (module_key);


--
-- Name: index_role_permissions_on_permission_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_role_permissions_on_permission_key ON public.role_permissions USING btree (permission_key);


--
-- Name: index_sessions_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sessions_on_token_digest ON public.sessions USING btree (token_digest);


--
-- Name: index_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_user_id ON public.sessions USING btree (user_id);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: uq_appointment_services_position; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_appointment_services_position ON public.appointment_services USING btree (organization_id, company_id, appointment_id, "position");


--
-- Name: uq_branches_organization_id_company_id_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_branches_organization_id_company_id_id ON public.branches USING btree (organization_id, company_id, id);


--
-- Name: uq_bso_branch_service; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_bso_branch_service ON public.branch_service_overrides USING btree (branch_id, service_id);


--
-- Name: uq_companies_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_companies_slug ON public.companies USING btree (slug);


--
-- Name: uq_customers_company_phone; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_customers_company_phone ON public.customers USING btree (company_id, phone_e164);


--
-- Name: uq_customers_org_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_customers_org_company_id ON public.customers USING btree (organization_id, company_id, id);


--
-- Name: uq_idempotency_keys_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_idempotency_keys_scope ON public.idempotency_keys USING btree (organization_id, principal_key, key);


--
-- Name: uq_import_batches_running; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_import_batches_running ON public.import_batches USING btree (organization_id, company_id, kind) WHERE ((status)::text = ANY ((ARRAY['queued'::character varying, 'processing'::character varying])::text[]));


--
-- Name: uq_import_rows_batch_row; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_import_rows_batch_row ON public.import_rows USING btree (organization_id, import_batch_id, row_number);


--
-- Name: uq_memberships_user_role_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_memberships_user_role_scope ON public.memberships USING btree (organization_id, user_id, role_id, company_id, branch_id) NULLS NOT DISTINCT;


--
-- Name: uq_pba_org_company_professional_branch; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_pba_org_company_professional_branch ON public.professional_branch_assignments USING btree (organization_id, company_id, professional_id, branch_id);


--
-- Name: uq_pba_professional_branch; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_pba_professional_branch ON public.professional_branch_assignments USING btree (professional_id, branch_id);


--
-- Name: uq_processed_events_event_subscriber; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_processed_events_event_subscriber ON public.processed_events USING btree (event_id, subscriber);


--
-- Name: uq_professionals_company_user; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_professionals_company_user ON public.professionals USING btree (company_id, user_id) WHERE ((user_id IS NOT NULL) AND (archived_at IS NULL));


--
-- Name: uq_professionals_org_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_professionals_org_company_id ON public.professionals USING btree (organization_id, company_id, id);


--
-- Name: uq_ps_professional_service; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_ps_professional_service ON public.professional_services USING btree (professional_id, service_id);


--
-- Name: uq_resources_org_branch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_resources_org_branch_id ON public.resources USING btree (organization_id, branch_id, id);


--
-- Name: uq_resources_org_company_branch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_resources_org_company_branch_id ON public.resources USING btree (organization_id, company_id, branch_id, id);


--
-- Name: uq_resources_org_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_resources_org_company_id ON public.resources USING btree (organization_id, company_id, id);


--
-- Name: uq_roles_id_scope_level; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_roles_id_scope_level ON public.roles USING btree (id, scope_level);


--
-- Name: uq_roles_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_roles_key ON public.roles USING btree (key);


--
-- Name: uq_services_organization_id_company_id_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_services_organization_id_company_id_id ON public.services USING btree (organization_id, company_id, id);


--
-- Name: uq_srr_service_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_srr_service_kind ON public.service_resource_requirements USING btree (service_id, kind);


--
-- Name: appointment_services appointment_services_reject_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER appointment_services_reject_update BEFORE UPDATE ON public.appointment_services FOR EACH STATEMENT EXECUTE FUNCTION public.reject_row_update();


--
-- Name: audit_events audit_events_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_events_append_only BEFORE DELETE OR UPDATE OR TRUNCATE ON public.audit_events FOR EACH STATEMENT EXECUTE FUNCTION public.reject_audit_mutation();


--
-- Name: auth_audit_events auth_audit_events_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER auth_audit_events_append_only BEFORE DELETE OR UPDATE OR TRUNCATE ON public.auth_audit_events FOR EACH STATEMENT EXECUTE FUNCTION public.reject_audit_mutation();


--
-- Name: appointment_services fk_appointment_services_appointment; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointment_services
    ADD CONSTRAINT fk_appointment_services_appointment FOREIGN KEY (organization_id, company_id, appointment_id) REFERENCES public.appointments(organization_id, company_id, id) ON DELETE CASCADE;


--
-- Name: appointment_services fk_appointment_services_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointment_services
    ADD CONSTRAINT fk_appointment_services_company FOREIGN KEY (organization_id, company_id) REFERENCES public.companies(organization_id, id) ON DELETE RESTRICT;


--
-- Name: appointment_services fk_appointment_services_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointment_services
    ADD CONSTRAINT fk_appointment_services_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: appointment_services fk_appointment_services_service; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointment_services
    ADD CONSTRAINT fk_appointment_services_service FOREIGN KEY (organization_id, company_id, service_id) REFERENCES public.services(organization_id, company_id, id);


--
-- Name: appointments fk_appointments_branch; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT fk_appointments_branch FOREIGN KEY (organization_id, company_id, branch_id) REFERENCES public.branches(organization_id, company_id, id);


--
-- Name: appointments fk_appointments_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT fk_appointments_company FOREIGN KEY (organization_id, company_id) REFERENCES public.companies(organization_id, id) ON DELETE RESTRICT;


--
-- Name: appointments fk_appointments_customer; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT fk_appointments_customer FOREIGN KEY (organization_id, company_id, customer_id) REFERENCES public.customers(organization_id, company_id, id);


--
-- Name: appointments fk_appointments_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT fk_appointments_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: appointments fk_appointments_professional; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT fk_appointments_professional FOREIGN KEY (organization_id, company_id, professional_id) REFERENCES public.professionals(organization_id, company_id, id);


--
-- Name: appointments fk_appointments_rescheduled_from; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT fk_appointments_rescheduled_from FOREIGN KEY (organization_id, company_id, rescheduled_from_id) REFERENCES public.appointments(organization_id, company_id, id);


--
-- Name: appointments fk_appointments_resource; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT fk_appointments_resource FOREIGN KEY (organization_id, branch_id, resource_id) REFERENCES public.resources(organization_id, branch_id, id);


--
-- Name: audit_events fk_audit_events_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_events
    ADD CONSTRAINT fk_audit_events_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: branch_module_settings fk_branch_module_settings_branch; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branch_module_settings
    ADD CONSTRAINT fk_branch_module_settings_branch FOREIGN KEY (organization_id, company_id, branch_id) REFERENCES public.branches(organization_id, company_id, id);


--
-- Name: branch_module_settings fk_branch_module_settings_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branch_module_settings
    ADD CONSTRAINT fk_branch_module_settings_company FOREIGN KEY (organization_id, company_id) REFERENCES public.companies(organization_id, id) ON DELETE RESTRICT;


--
-- Name: branch_module_settings fk_branch_module_settings_company_module; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branch_module_settings
    ADD CONSTRAINT fk_branch_module_settings_company_module FOREIGN KEY (organization_id, company_id, module_key) REFERENCES public.company_modules(organization_id, company_id, module_key);


--
-- Name: branch_module_settings fk_branch_module_settings_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branch_module_settings
    ADD CONSTRAINT fk_branch_module_settings_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: branch_service_overrides fk_branch_service_overrides_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branch_service_overrides
    ADD CONSTRAINT fk_branch_service_overrides_company FOREIGN KEY (organization_id, company_id) REFERENCES public.companies(organization_id, id) ON DELETE RESTRICT;


--
-- Name: branch_service_overrides fk_branch_service_overrides_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branch_service_overrides
    ADD CONSTRAINT fk_branch_service_overrides_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: branches fk_branches_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT fk_branches_company FOREIGN KEY (organization_id, company_id) REFERENCES public.companies(organization_id, id) ON DELETE RESTRICT;


--
-- Name: branches fk_branches_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branches
    ADD CONSTRAINT fk_branches_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: branch_service_overrides fk_bso_branch; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branch_service_overrides
    ADD CONSTRAINT fk_bso_branch FOREIGN KEY (organization_id, company_id, branch_id) REFERENCES public.branches(organization_id, company_id, id);


--
-- Name: branch_service_overrides fk_bso_service; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.branch_service_overrides
    ADD CONSTRAINT fk_bso_service FOREIGN KEY (organization_id, company_id, service_id) REFERENCES public.services(organization_id, company_id, id);


--
-- Name: companies fk_companies_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT fk_companies_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: company_modules fk_company_modules_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_modules
    ADD CONSTRAINT fk_company_modules_company FOREIGN KEY (organization_id, company_id) REFERENCES public.companies(organization_id, id) ON DELETE RESTRICT;


--
-- Name: company_modules fk_company_modules_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.company_modules
    ADD CONSTRAINT fk_company_modules_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: customers fk_customers_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT fk_customers_company FOREIGN KEY (organization_id, company_id) REFERENCES public.companies(organization_id, id) ON DELETE RESTRICT;


--
-- Name: customers fk_customers_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT fk_customers_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: idempotency_keys fk_idempotency_keys_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idempotency_keys
    ADD CONSTRAINT fk_idempotency_keys_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: import_batches fk_import_batches_branch; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_batches
    ADD CONSTRAINT fk_import_batches_branch FOREIGN KEY (organization_id, branch_id) REFERENCES public.branches(organization_id, id) ON DELETE RESTRICT;


--
-- Name: import_batches fk_import_batches_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_batches
    ADD CONSTRAINT fk_import_batches_company FOREIGN KEY (organization_id, company_id) REFERENCES public.companies(organization_id, id) ON DELETE RESTRICT;


--
-- Name: import_batches fk_import_batches_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_batches
    ADD CONSTRAINT fk_import_batches_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: import_rows fk_import_rows_import_batch; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_rows
    ADD CONSTRAINT fk_import_rows_import_batch FOREIGN KEY (organization_id, import_batch_id) REFERENCES public.import_batches(organization_id, id) ON DELETE RESTRICT;


--
-- Name: import_rows fk_import_rows_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_rows
    ADD CONSTRAINT fk_import_rows_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: memberships fk_memberships_branch; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_memberships_branch FOREIGN KEY (organization_id, company_id, branch_id) REFERENCES public.branches(organization_id, company_id, id);


--
-- Name: memberships fk_memberships_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_memberships_company FOREIGN KEY (organization_id, company_id) REFERENCES public.companies(organization_id, id) ON DELETE RESTRICT;


--
-- Name: memberships fk_memberships_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_memberships_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: memberships fk_memberships_role_scope; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_memberships_role_scope FOREIGN KEY (role_id, scope_level) REFERENCES public.roles(id, scope_level);


--
-- Name: memberships fk_memberships_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_memberships_user FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: outbox_events fk_outbox_events_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbox_events
    ADD CONSTRAINT fk_outbox_events_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: professional_branch_assignments fk_pba_branch; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.professional_branch_assignments
    ADD CONSTRAINT fk_pba_branch FOREIGN KEY (organization_id, company_id, branch_id) REFERENCES public.branches(organization_id, company_id, id);


--
-- Name: professional_branch_assignments fk_pba_professional; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.professional_branch_assignments
    ADD CONSTRAINT fk_pba_professional FOREIGN KEY (organization_id, company_id, professional_id) REFERENCES public.professionals(organization_id, company_id, id);


--
-- Name: processed_events fk_processed_events_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processed_events
    ADD CONSTRAINT fk_processed_events_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: professional_branch_assignments fk_professional_branch_assignments_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.professional_branch_assignments
    ADD CONSTRAINT fk_professional_branch_assignments_company FOREIGN KEY (organization_id, company_id) REFERENCES public.companies(organization_id, id) ON DELETE RESTRICT;


--
-- Name: professional_branch_assignments fk_professional_branch_assignments_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.professional_branch_assignments
    ADD CONSTRAINT fk_professional_branch_assignments_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: professional_services fk_professional_services_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.professional_services
    ADD CONSTRAINT fk_professional_services_company FOREIGN KEY (organization_id, company_id) REFERENCES public.companies(organization_id, id) ON DELETE RESTRICT;


--
-- Name: professional_services fk_professional_services_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.professional_services
    ADD CONSTRAINT fk_professional_services_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: professionals fk_professionals_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.professionals
    ADD CONSTRAINT fk_professionals_company FOREIGN KEY (organization_id, company_id) REFERENCES public.companies(organization_id, id) ON DELETE RESTRICT;


--
-- Name: professionals fk_professionals_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.professionals
    ADD CONSTRAINT fk_professionals_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: professionals fk_professionals_user; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.professionals
    ADD CONSTRAINT fk_professionals_user FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: professional_services fk_ps_professional; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.professional_services
    ADD CONSTRAINT fk_ps_professional FOREIGN KEY (organization_id, company_id, professional_id) REFERENCES public.professionals(organization_id, company_id, id);


--
-- Name: professional_services fk_ps_service; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.professional_services
    ADD CONSTRAINT fk_ps_service FOREIGN KEY (organization_id, company_id, service_id) REFERENCES public.services(organization_id, company_id, id);


--
-- Name: sessions fk_rails_758836b4f0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_758836b4f0 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: resources fk_resources_branch; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resources
    ADD CONSTRAINT fk_resources_branch FOREIGN KEY (organization_id, company_id, branch_id) REFERENCES public.branches(organization_id, company_id, id);


--
-- Name: resources fk_resources_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resources
    ADD CONSTRAINT fk_resources_company FOREIGN KEY (organization_id, company_id) REFERENCES public.companies(organization_id, id) ON DELETE RESTRICT;


--
-- Name: resources fk_resources_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resources
    ADD CONSTRAINT fk_resources_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: role_permissions fk_role_permissions_permission; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT fk_role_permissions_permission FOREIGN KEY (permission_key) REFERENCES public.permissions(key) ON DELETE CASCADE;


--
-- Name: role_permissions fk_role_permissions_role; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT fk_role_permissions_role FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE CASCADE;


--
-- Name: service_resource_requirements fk_service_resource_requirements_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_resource_requirements
    ADD CONSTRAINT fk_service_resource_requirements_company FOREIGN KEY (organization_id, company_id) REFERENCES public.companies(organization_id, id) ON DELETE RESTRICT;


--
-- Name: service_resource_requirements fk_service_resource_requirements_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_resource_requirements
    ADD CONSTRAINT fk_service_resource_requirements_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: services fk_services_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.services
    ADD CONSTRAINT fk_services_company FOREIGN KEY (organization_id, company_id) REFERENCES public.companies(organization_id, id) ON DELETE RESTRICT;


--
-- Name: services fk_services_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.services
    ADD CONSTRAINT fk_services_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: service_resource_requirements fk_srr_service; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_resource_requirements
    ADD CONSTRAINT fk_srr_service FOREIGN KEY (organization_id, company_id, service_id) REFERENCES public.services(organization_id, company_id, id);


--
-- Name: time_offs fk_time_offs_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_offs
    ADD CONSTRAINT fk_time_offs_company FOREIGN KEY (organization_id, company_id) REFERENCES public.companies(organization_id, id) ON DELETE RESTRICT;


--
-- Name: time_offs fk_time_offs_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_offs
    ADD CONSTRAINT fk_time_offs_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: time_offs fk_time_offs_professional; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_offs
    ADD CONSTRAINT fk_time_offs_professional FOREIGN KEY (organization_id, company_id, professional_id) REFERENCES public.professionals(organization_id, company_id, id);


--
-- Name: time_offs fk_time_offs_resource; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_offs
    ADD CONSTRAINT fk_time_offs_resource FOREIGN KEY (organization_id, company_id, resource_id) REFERENCES public.resources(organization_id, company_id, id);


--
-- Name: weekly_schedules fk_weekly_schedules_company; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_schedules
    ADD CONSTRAINT fk_weekly_schedules_company FOREIGN KEY (organization_id, company_id) REFERENCES public.companies(organization_id, id) ON DELETE RESTRICT;


--
-- Name: weekly_schedules fk_weekly_schedules_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_schedules
    ADD CONSTRAINT fk_weekly_schedules_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: weekly_schedules fk_ws_assignment; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_schedules
    ADD CONSTRAINT fk_ws_assignment FOREIGN KEY (organization_id, company_id, professional_id, branch_id) REFERENCES public.professional_branch_assignments(organization_id, company_id, professional_id, branch_id);


--
-- Name: weekly_schedules fk_ws_branch; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_schedules
    ADD CONSTRAINT fk_ws_branch FOREIGN KEY (organization_id, company_id, branch_id) REFERENCES public.branches(organization_id, company_id, id);


--
-- Name: weekly_schedules fk_ws_resource; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_schedules
    ADD CONSTRAINT fk_ws_resource FOREIGN KEY (organization_id, company_id, branch_id, resource_id) REFERENCES public.resources(organization_id, company_id, branch_id, id);


--
-- Name: appointment_services tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.appointment_services USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- Name: appointments tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.appointments USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- Name: audit_events tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.audit_events USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- Name: branch_module_settings tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.branch_module_settings USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- Name: branch_service_overrides tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.branch_service_overrides USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- Name: branches tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.branches USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- Name: companies tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.companies USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- Name: company_modules tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.company_modules USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- Name: customers tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.customers USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- Name: idempotency_keys tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.idempotency_keys USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- Name: import_batches tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.import_batches USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- Name: import_rows tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.import_rows USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- Name: memberships tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.memberships USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- Name: outbox_events tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.outbox_events USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- Name: processed_events tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.processed_events USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- Name: professional_branch_assignments tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.professional_branch_assignments USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- Name: professional_services tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.professional_services USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- Name: professionals tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.professionals USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- Name: resources tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.resources USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- Name: service_resource_requirements tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.service_resource_requirements USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- Name: services tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.services USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- Name: time_offs tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.time_offs USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- Name: weekly_schedules tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.weekly_schedules USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261123145051'),
('20261123145050'),
('20261117210801'),
('20261117210800'),
('20261117210720'),
('20261116210048'),
('20261116210047'),
('20261113051330'),
('20261113051328'),
('20261113051326'),
('20261113051324'),
('20261112100700'),
('20261112100600'),
('20261112100500'),
('20261112100400'),
('20261112100300'),
('20261112100200'),
('20261112100100'),
('20261112100000'),
('20261112021801'),
('20261111180300'),
('20261111180200'),
('20261111180100'),
('20261111180000'),
('20261111171200'),
('20261111171100'),
('20261111171000'),
('20261111030100'),
('20261111030000'),
('20261111024137'),
('20261110100300'),
('20261110100200'),
('20261110100100'),
('20261110100000'),
('20261110000200'),
('20261110000100'),
('20261110000000'),
('20261109000200'),
('20261109000100'),
('20261109000000'),
('20261108210100'),
('20261108210000'),
('20261108200100'),
('20261108200000'),
('20261108100200'),
('20261108100100'),
('20261108100000'),
('20261108000000');

