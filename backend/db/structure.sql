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


SET default_tablespace = '';

SET default_table_access_method = heap;

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
    CONSTRAINT chk_companies_currency CHECK (((currency)::text = ANY (ARRAY[('NIO'::character varying)::text, ('USD'::character varying)::text]))),
    CONSTRAINT chk_companies_slug_format CHECK (((slug)::text ~ '^[a-z0-9-]{3,40}$'::text)),
    CONSTRAINT chk_companies_status CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('inactive'::character varying)::text])))
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
    CONSTRAINT chk_organizations_status CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('suspended'::character varying)::text])))
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
    CONSTRAINT chk_roles_scope_level CHECK (((scope_level)::text = ANY (ARRAY[('organization'::character varying)::text, ('company'::character varying)::text, ('branch'::character varying)::text])))
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
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
-- Name: idempotency_keys idempotency_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idempotency_keys
    ADD CONSTRAINT idempotency_keys_pkey PRIMARY KEY (id);


--
-- Name: memberships memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT memberships_pkey PRIMARY KEY (id);


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
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: audit_events uq_audit_events_organization_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_events
    ADD CONSTRAINT uq_audit_events_organization_id_id UNIQUE (organization_id, id);


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
-- Name: idempotency_keys uq_idempotency_keys_organization_id_id; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idempotency_keys
    ADD CONSTRAINT uq_idempotency_keys_organization_id_id UNIQUE (organization_id, id);


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
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


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
-- Name: idx_idempotency_keys_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_idempotency_keys_expires_at ON public.idempotency_keys USING btree (expires_at);


--
-- Name: idx_outbox_events_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_outbox_events_pending ON public.outbox_events USING btree (id) WHERE (published_at IS NULL);


--
-- Name: idx_outbox_events_published_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_outbox_events_published_at ON public.outbox_events USING btree (published_at) WHERE (published_at IS NOT NULL);


--
-- Name: idx_processed_events_processed_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_processed_events_processed_at ON public.processed_events USING btree (processed_at);


--
-- Name: index_branches_on_organization_id_and_company_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_branches_on_organization_id_and_company_id ON public.branches USING btree (organization_id, company_id);


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
-- Name: uq_branches_organization_id_company_id_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_branches_organization_id_company_id_id ON public.branches USING btree (organization_id, company_id, id);


--
-- Name: uq_companies_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_companies_slug ON public.companies USING btree (slug);


--
-- Name: uq_idempotency_keys_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_idempotency_keys_scope ON public.idempotency_keys USING btree (organization_id, principal_key, key);


--
-- Name: uq_memberships_user_role_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_memberships_user_role_scope ON public.memberships USING btree (organization_id, user_id, role_id, company_id, branch_id) NULLS NOT DISTINCT;


--
-- Name: uq_processed_events_event_subscriber; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_processed_events_event_subscriber ON public.processed_events USING btree (event_id, subscriber);


--
-- Name: uq_roles_id_scope_level; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_roles_id_scope_level ON public.roles USING btree (id, scope_level);


--
-- Name: uq_roles_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_roles_key ON public.roles USING btree (key);


--
-- Name: audit_events audit_events_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER audit_events_append_only BEFORE DELETE OR UPDATE OR TRUNCATE ON public.audit_events FOR EACH STATEMENT EXECUTE FUNCTION public.reject_audit_mutation();


--
-- Name: auth_audit_events auth_audit_events_append_only; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER auth_audit_events_append_only BEFORE DELETE OR UPDATE OR TRUNCATE ON public.auth_audit_events FOR EACH STATEMENT EXECUTE FUNCTION public.reject_audit_mutation();


--
-- Name: audit_events fk_audit_events_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_events
    ADD CONSTRAINT fk_audit_events_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


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
-- Name: companies fk_companies_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.companies
    ADD CONSTRAINT fk_companies_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: idempotency_keys fk_idempotency_keys_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idempotency_keys
    ADD CONSTRAINT fk_idempotency_keys_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


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
-- Name: processed_events fk_processed_events_organization; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.processed_events
    ADD CONSTRAINT fk_processed_events_organization FOREIGN KEY (organization_id) REFERENCES public.organizations(id) ON DELETE RESTRICT;


--
-- Name: sessions fk_rails_758836b4f0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_758836b4f0 FOREIGN KEY (user_id) REFERENCES public.users(id);


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
-- Name: audit_events tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.audit_events USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- Name: branches tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.branches USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- Name: companies tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.companies USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


--
-- Name: idempotency_keys tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation ON public.idempotency_keys USING ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid)) WITH CHECK ((organization_id = (NULLIF(current_setting('app.organization_id'::text, true), ''::text))::uuid));


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
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
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

