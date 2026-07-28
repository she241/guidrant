(function () {
  const cfg = window.GUIDRENT_CONFIG || {};
  const configured = Boolean(cfg.SUPABASE_URL && cfg.SUPABASE_PUBLISHABLE_KEY && window.supabase?.createClient);
  const apiEnabled = Boolean(cfg.API_URL && String(cfg.API_URL).trim());
  const client = configured
    ? window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_PUBLISHABLE_KEY)
    : null;

  async function requireSession() {
    if (!client) throw new Error('Supabase is not configured.');
    const { data, error } = await client.auth.getSession();
    if (error) throw error;
    if (!data.session) throw new Error('Please sign in first.');
    return data.session;
  }

  function result(data, error, message = 'Backend request failed.') {
    if (error) throw new Error(error.message || message);
    return data;
  }

  async function api(path, options = {}) {
    if (!apiEnabled) throw new Error('The optional API server is not configured.');
    const session = await requireSession();
    const response = await fetch(`${String(cfg.API_URL).replace(/\/$/, '')}${path}`, {
      ...options,
      headers: {
        'content-type': 'application/json',
        Authorization: `Bearer ${session.access_token}`,
        ...(options.headers || {})
      }
    });
    const payload = response.status === 204 ? null : await response.json();
    if (!response.ok) throw new Error(payload?.error || 'Backend request failed.');
    return payload;
  }

  function mapProperty(row) {
    const frequency = row.rent_frequency === 'nightly' ? 'night' : row.rent_frequency === 'yearly' ? 'year' : 'month';
    const money = new Intl.NumberFormat('en-GH', {
      style: 'currency',
      currency: row.currency || 'GHS',
      maximumFractionDigits: 0
    }).format(Number(row.price));
    return {
      id: row.id,
      title: row.title,
      area: row.area,
      city: row.city,
      price: Number(row.price),
      priceLabel: `${money} / ${frequency}`,
      beds: row.bedrooms,
      baths: row.bathrooms,
      toilets: row.toilets || row.bathrooms,
      parking: row.parking || 0,
      type: row.property_type,
      furnishing: row.furnished ? 'Furnished' : 'Unfurnished',
      verified: row.is_verified,
      featured: row.is_featured,
      posted: new Date(row.created_at).toLocaleDateString('en-GH', { day: 'numeric', month: 'short', year: 'numeric' }),
      agent: row.agent_name || row.source_agent_name || 'Guidrent agent',
      source: row.source_name || 'Guidrent',
      sourceUrl: row.source_url || '#',
      sourcePhoto: Boolean(row.source_url),
      image: row.cover_url || 'assets/guidrent-icon.png',
      lat: row.latitude,
      lng: row.longitude,
      summary: row.description || '',
      amenities: row.amenities || [],
      gallery: [row.cover_url].filter(Boolean)
    };
  }

  async function directProfileUpdate(table, keyColumn, keyValue, payload) {
    await requireSession();
    return result(...Object.values(await client.from(table).upsert({ [keyColumn]: keyValue, ...payload }).select('*').single()));
  }

  const backend = {
    configured,
    apiEnabled,
    client,
    mapProperty,

    async signUp({ email, password, fullName, role = 'seeker' }) {
      if (!client) throw new Error('Supabase is not configured.');
      const { data, error } = await client.auth.signUp({
        email,
        password,
        options: { data: { full_name: fullName, role } }
      });
      if (error) throw error;
      return data;
    },

    async signIn(email, password) {
      if (!client) throw new Error('Supabase is not configured.');
      const { data, error } = await client.auth.signInWithPassword({ email, password });
      if (error) throw error;
      return data;
    },

    async signOut() {
      if (!client) return;
      const { error } = await client.auth.signOut();
      if (error) throw error;
    },

    async currentUser() {
      if (!client) return null;
      const { data, error } = await client.auth.getUser();
      if (error) return null;
      return data.user || null;
    },

    async listProperties(filters = {}) {
      if (!client) return [];
      const { data, error } = await client.rpc('search_properties', {
        p_query: filters.q || null,
        p_area: filters.area || null,
        p_min_price: filters.minPrice ?? null,
        p_max_price: filters.maxPrice ?? null,
        p_bedrooms: filters.bedrooms ?? null,
        p_property_type: filters.propertyType || null,
        p_furnished: filters.furnished ?? null,
        p_limit: filters.limit || 100,
        p_offset: filters.offset || 0
      });
      if (error) throw error;
      return data.map(mapProperty);
    },

    async getMyProfile() {
      const session = await requireSession();
      if (apiEnabled) return api('/api/me');
      const { data: profile, error: profileError } = await client.from('profiles')
        .select('*').eq('id', session.user.id).single();
      result(profile, profileError);
      let roleProfile = null;
      if (profile.role === 'agent') {
        const { data, error } = await client.from('agent_profiles').select('*').eq('user_id', session.user.id).maybeSingle();
        roleProfile = result(data, error);
      } else if (profile.role === 'seeker') {
        const { data, error } = await client.from('seeker_profiles').select('*').eq('user_id', session.user.id).maybeSingle();
        roleProfile = result(data, error);
      }
      return { data: { auth: { id: session.user.id, email: session.user.email }, profile, role_profile: roleProfile } };
    },

    async listFavorites() {
      const session = await requireSession();
      if (apiEnabled) return api('/api/favorites');
      const { data: rows, error } = await client.from('favorites').select('property_id, created_at')
        .eq('user_id', session.user.id).order('created_at', { ascending: false });
      result(rows, error);
      const ids = rows.map(row => row.property_id);
      if (!ids.length) return { data: [] };
      const { data: cards, error: cardsError } = await client.from('property_cards').select('*').in('id', ids);
      result(cards, cardsError);
      const byId = new Map(cards.map(card => [card.id, card]));
      return { data: rows.map(row => ({ ...row, property: byId.get(row.property_id) || null })) };
    },

    async listTours() {
      const session = await requireSession();
      if (apiEnabled) return api('/api/tours');
      const { data, error } = await client.from('tour_requests')
        .select('*, property:properties(id,title,slug,area,price,currency)')
        .or(`seeker_id.eq.${session.user.id},agent_id.eq.${session.user.id}`)
        .order('created_at', { ascending: false });
      return { data: result(data, error) };
    },

    async saveFavorite(propertyId) {
      const session = await requireSession();
      if (apiEnabled) return api(`/api/favorites/${propertyId}`, { method: 'POST', body: '{}' });
      const { data, error } = await client.from('favorites')
        .upsert({ user_id: session.user.id, property_id: propertyId })
        .select('*').single();
      return { data: result(data, error) };
    },

    async removeFavorite(propertyId) {
      const session = await requireSession();
      if (apiEnabled) return api(`/api/favorites/${propertyId}`, { method: 'DELETE' });
      const { error } = await client.from('favorites').delete()
        .eq('user_id', session.user.id).eq('property_id', propertyId);
      result(null, error);
      return null;
    },

    async requestTour(input) {
      const session = await requireSession();
      let response;
      if (apiEnabled) {
        response = await api('/api/tours', { method: 'POST', body: JSON.stringify(input) });
      } else {
        const { data, error } = await client.from('tour_requests')
          .insert({ ...input, seeker_id: session.user.id }).select('*').single();
        response = { data: result(data, error) };
      }
      if (client && response?.data?.id) {
        await client.functions.invoke('notify-tour', { body: { tour_id: response.data.id } }).catch(() => null);
      }
      return response;
    },

    async createProperty(input) {
      const session = await requireSession();
      if (apiEnabled) return api('/api/properties', { method: 'POST', body: JSON.stringify(input) });
      const { data, error } = await client.from('properties')
        .insert({ ...input, agent_id: session.user.id }).select('*').single();
      return { data: result(data, error) };
    },

    async uploadPropertyPhotos(propertyId, files) {
      const session = await requireSession();
      const uploaded = [];
      for (let index = 0; index < files.length; index += 1) {
        const file = files[index];
        const safeName = `${crypto.randomUUID()}-${file.name.replace(/[^a-zA-Z0-9._-]/g, '-')}`;
        const path = `${propertyId}/${session.user.id}/${safeName}`;
        const { error: uploadError } = await client.storage.from('property-images').upload(path, file, { upsert: false });
        if (uploadError) throw uploadError;
        const { data: publicUrlData } = client.storage.from('property-images').getPublicUrl(path);
        const photoPayload = {
          property_id: propertyId,
          storage_path: path,
          external_url: publicUrlData.publicUrl,
          sort_order: index,
          is_cover: index === 0
        };
        let photo;
        if (apiEnabled) {
          const registered = await api(`/api/properties/${propertyId}/photos`, {
            method: 'POST',
            body: JSON.stringify(photoPayload)
          });
          photo = registered.data;
        } else {
          const { data, error } = await client.from('property_photos').insert(photoPayload).select('*').single();
          photo = result(data, error);
        }
        uploaded.push(photo);
      }
      return uploaded;
    },

    async uploadAvatar(file) {
      const session = await requireSession();
      const ext = (file.name.split('.').pop() || 'png').replace(/[^a-zA-Z0-9]/g, '');
      const path = `${session.user.id}/avatar-${crypto.randomUUID()}.${ext}`;
      const { error: uploadError } = await client.storage.from('avatars').upload(path, file, { upsert: false });
      if (uploadError) throw uploadError;
      const { data: urlData } = client.storage.from('avatars').getPublicUrl(path);
      await client.from('profiles').update({ avatar_url: urlData.publicUrl }).eq('id', session.user.id);
      return urlData.publicUrl;
    },

    async uploadAgentVerification(documentType, file) {
      const session = await requireSession();
      const safeName = `${crypto.randomUUID()}-${file.name.replace(/[^a-zA-Z0-9._-]/g, '-')}`;
      const path = `${session.user.id}/${safeName}`;
      const { error: uploadError } = await client.storage.from('verification-documents').upload(path, file, { upsert: false });
      if (uploadError) throw uploadError;
      const { data, error } = await client.from('agent_verification_documents')
        .insert({ agent_id: session.user.id, document_type: documentType, storage_path: path })
        .select('*').single();
      return { data: result(data, error) };
    },

    async uploadApplicationDocument(applicationId, documentType, file) {
      const session = await requireSession();
      const safeName = `${crypto.randomUUID()}-${file.name.replace(/[^a-zA-Z0-9._-]/g, '-')}`;
      const path = `${session.user.id}/${applicationId}/${safeName}`;
      const { error: uploadError } = await client.storage.from('application-documents').upload(path, file, { upsert: false });
      if (uploadError) throw uploadError;
      const payload = { document_type: documentType, storage_path: path, original_filename: file.name, mime_type: file.type, file_size_bytes: file.size };
      if (apiEnabled) return api(`/api/applications/${applicationId}/documents`, { method: 'POST', body: JSON.stringify(payload) });
      const { data, error } = await client.from('application_documents')
        .insert({ ...payload, application_id: applicationId, applicant_id: session.user.id }).select('*').single();
      return { data: result(data, error) };
    },

    async updateProfile(input) {
      const session = await requireSession();
      if (apiEnabled) return api('/api/me', { method: 'PATCH', body: JSON.stringify(input) });
      const { data, error } = await client.from('profiles').update(input).eq('id', session.user.id).select('*').single();
      return { data: result(data, error) };
    },

    async updateSeekerProfile(input) {
      const session = await requireSession();
      if (apiEnabled) return api('/api/me/seeker', { method: 'PATCH', body: JSON.stringify(input) });
      const { data, error } = await client.from('seeker_profiles').upsert({ user_id: session.user.id, ...input }).select('*').single();
      return { data: result(data, error) };
    },

    async updateAgentProfile(input) {
      const session = await requireSession();
      if (apiEnabled) return api('/api/me/agent', { method: 'PATCH', body: JSON.stringify(input) });
      const { data, error } = await client.from('agent_profiles').upsert({ user_id: session.user.id, ...input }).select('*').single();
      return { data: result(data, error) };
    },

    async startConversation(propertyId, agentId) {
      const session = await requireSession();
      if (apiEnabled) return api('/api/messages/conversations', { method: 'POST', body: JSON.stringify({ property_id: propertyId, agent_id: agentId }) });
      const { data, error } = await client.from('conversations')
        .upsert({ property_id: propertyId, agent_id: agentId, seeker_id: session.user.id }, { onConflict: 'property_id,seeker_id,agent_id' })
        .select('*').single();
      return { data: result(data, error) };
    },

    async sendMessage(conversationId, body) {
      const session = await requireSession();
      if (apiEnabled) return api(`/api/messages/conversations/${conversationId}/messages`, { method: 'POST', body: JSON.stringify({ body }) });
      const { data, error } = await client.from('messages')
        .insert({ conversation_id: conversationId, sender_id: session.user.id, body }).select('*').single();
      result(data, error);
      await client.from('conversations').update({ last_message_at: new Date().toISOString() }).eq('id', conversationId);
      return { data };
    },

    async listSavedSearches() {
      const session = await requireSession();
      if (apiEnabled) return api('/api/saved-searches');
      const { data, error } = await client.from('saved_searches').select('*')
        .eq('user_id', session.user.id).order('created_at', { ascending: false });
      return { data: result(data, error) };
    },

    async saveSearch(input) {
      const session = await requireSession();
      if (apiEnabled) return api('/api/saved-searches', { method: 'POST', body: JSON.stringify(input) });
      const { data, error } = await client.from('saved_searches')
        .insert({ ...input, user_id: session.user.id }).select('*').single();
      return { data: result(data, error) };
    },

    async listApplications() {
      await requireSession();
      if (apiEnabled) return api('/api/applications');
      const { data, error } = await client.from('rental_applications')
        .select('*, property:properties(id,title,slug,area,price,currency,status)')
        .order('created_at', { ascending: false });
      return { data: result(data, error) };
    },

    async submitApplication(input) {
      const session = await requireSession();
      if (apiEnabled) return api('/api/applications', { method: 'POST', body: JSON.stringify(input) });
      const { data, error } = await client.from('rental_applications')
        .upsert({ ...input, applicant_id: session.user.id }, { onConflict: 'property_id,applicant_id' })
        .select('*').single();
      result(data, error);
      await client.rpc('record_property_event', { p_property_id: input.property_id, p_event: 'application' }).catch(() => null);
      return { data };
    },

    async listNotifications(unreadOnly = false) {
      const session = await requireSession();
      if (apiEnabled) return api(`/api/notifications${unreadOnly ? '?unread=true' : ''}`);
      let query = client.from('notifications').select('*').eq('user_id', session.user.id)
        .order('created_at', { ascending: false }).limit(100);
      if (unreadOnly) query = query.is('read_at', null);
      const { data, error } = await query;
      return { data: result(data, error) };
    },

    async markNotificationRead(id) {
      const session = await requireSession();
      if (apiEnabled) return api(`/api/notifications/${id}/read`, { method: 'PATCH', body: '{}' });
      const { data, error } = await client.from('notifications')
        .update({ read_at: new Date().toISOString() }).eq('id', id).eq('user_id', session.user.id)
        .select('*').single();
      return { data: result(data, error) };
    },

    async getNotificationPreferences() {
      const session = await requireSession();
      if (apiEnabled) return api('/api/notifications/preferences');
      const { data, error } = await client.from('notification_preferences')
        .select('*').eq('user_id', session.user.id).maybeSingle();
      return { data: result(data, error) };
    },

    async updateNotificationPreferences(input) {
      const session = await requireSession();
      if (apiEnabled) return api('/api/notifications/preferences', { method: 'PUT', body: JSON.stringify(input) });
      const { data, error } = await client.from('notification_preferences')
        .upsert({ user_id: session.user.id, ...input }).select('*').single();
      return { data: result(data, error) };
    },

    async listAvailability(filters = {}) {
      if (apiEnabled) {
        const params = new URLSearchParams(Object.entries(filters).filter(([, value]) => value));
        const session = await client?.auth.getSession();
        if (session?.data?.session) return api(`/api/availability?${params}`);
      }
      if (!client) return { data: [] };
      let query = client.from('agent_availability').select('*').eq('active', true)
        .gte('starts_at', new Date().toISOString()).order('starts_at').limit(100);
      if (filters.property_id) query = query.eq('property_id', filters.property_id);
      if (filters.agent_id) query = query.eq('agent_id', filters.agent_id);
      const { data, error } = await query;
      return { data: result(data, error) };
    },

    async requestDataAction(requestType, details = null) {
      const session = await requireSession();
      if (apiEnabled) return api('/api/privacy/requests', { method: 'POST', body: JSON.stringify({ request_type: requestType, details }) });
      const { data, error } = await client.from('data_subject_requests')
        .insert({ user_id: session.user.id, request_type: requestType, details }).select('*').single();
      return { data: result(data, error) };
    },

    async recordConsent(consentType, policyVersion, granted) {
      const session = await requireSession();
      const payload = { consent_type: consentType, policy_version: policyVersion, granted, source: 'web' };
      if (apiEnabled) return api('/api/privacy/consent', { method: 'POST', body: JSON.stringify(payload) });
      const { data, error } = await client.from('consent_records')
        .insert({ ...payload, user_id: session.user.id, user_agent: navigator.userAgent }).select('*').single();
      return { data: result(data, error) };
    },

    async recordPropertyEvent(propertyId, event = 'view') {
      if (apiEnabled) {
        const response = await fetch(`${String(cfg.API_URL).replace(/\/$/, '')}/api/analytics/property-event`, {
          method: 'POST', headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ property_id: propertyId, event })
        });
        if (!response.ok) throw new Error('Unable to record property event.');
        return;
      }
      if (client) await client.rpc('record_property_event', { p_property_id: propertyId, p_event: event }).catch(() => null);
    },

    subscribeToMessages(conversationId, callback) {
      if (!client) return () => {};
      const channel = client.channel(`conversation:${conversationId}`)
        .on('postgres_changes', {
          event: 'INSERT', schema: 'public', table: 'messages', filter: `conversation_id=eq.${conversationId}`
        }, callback)
        .subscribe();
      return () => client.removeChannel(channel);
    }
  };

  window.GuidrentBackend = backend;
})();
