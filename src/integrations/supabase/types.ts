export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      api_keys: {
        Row: {
          active: boolean
          created_at: string
          id: string
          key_hash: string
          key_prefix: string
          label: string
          last_used_at: string | null
          user_id: string
          webhook_secret: string
        }
        Insert: {
          active?: boolean
          created_at?: string
          id?: string
          key_hash: string
          key_prefix: string
          label?: string
          last_used_at?: string | null
          user_id: string
          webhook_secret: string
        }
        Update: {
          active?: boolean
          created_at?: string
          id?: string
          key_hash?: string
          key_prefix?: string
          label?: string
          last_used_at?: string | null
          user_id?: string
          webhook_secret?: string
        }
        Relationships: []
      }
      gmail_connections: {
        Row: {
          access_token: string | null
          connected_at: string | null
          created_at: string
          email: string | null
          last_polled_at: string | null
          oauth_client_id: string | null
          oauth_client_secret: string | null
          refresh_token: string | null
          scope: string | null
          status: string
          token_expires_at: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          access_token?: string | null
          connected_at?: string | null
          created_at?: string
          email?: string | null
          last_polled_at?: string | null
          oauth_client_id?: string | null
          oauth_client_secret?: string | null
          refresh_token?: string | null
          scope?: string | null
          status?: string
          token_expires_at?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          access_token?: string | null
          connected_at?: string | null
          created_at?: string
          email?: string | null
          last_polled_at?: string | null
          oauth_client_id?: string | null
          oauth_client_secret?: string | null
          refresh_token?: string | null
          scope?: string | null
          status?: string
          token_expires_at?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      merchant_accounts: {
        Row: {
          app_password: string
          connected: boolean
          connected_at: string | null
          created_at: string
          email: string
          id: string
          last_polled_at: string | null
          payee_name: string
          provider: Database["public"]["Enums"]["upi_provider"]
          updated_at: string
          upi_id: string
          user_id: string
        }
        Insert: {
          app_password?: string
          connected?: boolean
          connected_at?: string | null
          created_at?: string
          email?: string
          id?: string
          last_polled_at?: string | null
          payee_name?: string
          provider: Database["public"]["Enums"]["upi_provider"]
          updated_at?: string
          upi_id?: string
          user_id: string
        }
        Update: {
          app_password?: string
          connected?: boolean
          connected_at?: string | null
          created_at?: string
          email?: string
          id?: string
          last_polled_at?: string | null
          payee_name?: string
          provider?: Database["public"]["Enums"]["upi_provider"]
          updated_at?: string
          upi_id?: string
          user_id?: string
        }
        Relationships: []
      }
      payment_links: {
        Row: {
          amount: number
          clicks: number
          created_at: string
          customer_name: string
          detected_at: string | null
          expires_at: string
          id: string
          link_type: string
          order_id: string
          paid_at: string | null
          paid_count: number
          paid_email_id: string | null
          payable_amount: number
          payee_name: string
          payer_email: string | null
          payer_name: string | null
          provider: Database["public"]["Enums"]["upi_provider"] | null
          slug: string
          status: Database["public"]["Enums"]["link_status"]
          upi_id: string
          user_id: string
          webhook_attempts: number
          webhook_delivered_at: string | null
          webhook_last_error: string | null
          webhook_url: string | null
        }
        Insert: {
          amount: number
          clicks?: number
          created_at?: string
          customer_name?: string
          detected_at?: string | null
          expires_at?: string
          id?: string
          link_type?: string
          order_id: string
          paid_at?: string | null
          paid_count?: number
          paid_email_id?: string | null
          payable_amount: number
          payee_name?: string
          payer_email?: string | null
          payer_name?: string | null
          provider?: Database["public"]["Enums"]["upi_provider"] | null
          slug: string
          status?: Database["public"]["Enums"]["link_status"]
          upi_id?: string
          user_id: string
          webhook_attempts?: number
          webhook_delivered_at?: string | null
          webhook_last_error?: string | null
          webhook_url?: string | null
        }
        Update: {
          amount?: number
          clicks?: number
          created_at?: string
          customer_name?: string
          detected_at?: string | null
          expires_at?: string
          id?: string
          link_type?: string
          order_id?: string
          paid_at?: string | null
          paid_count?: number
          paid_email_id?: string | null
          payable_amount?: number
          payee_name?: string
          payer_email?: string | null
          payer_name?: string | null
          provider?: Database["public"]["Enums"]["upi_provider"] | null
          slug?: string
          status?: Database["public"]["Enums"]["link_status"]
          upi_id?: string
          user_id?: string
          webhook_attempts?: number
          webhook_delivered_at?: string | null
          webhook_last_error?: string | null
          webhook_url?: string | null
        }
        Relationships: []
      }
      processed_emails: {
        Row: {
          amount: number | null
          created_at: string
          link_id: string | null
          message_id: string
          user_id: string | null
        }
        Insert: {
          amount?: number | null
          created_at?: string
          link_id?: string | null
          message_id: string
          user_id?: string | null
        }
        Update: {
          amount?: number | null
          created_at?: string
          link_id?: string | null
          message_id?: string
          user_id?: string | null
        }
        Relationships: []
      }
      profiles: {
        Row: {
          business_logo: string | null
          created_at: string
          full_name: string
          id: string
          mobile: string
          updated_at: string
        }
        Insert: {
          business_logo?: string | null
          created_at?: string
          full_name?: string
          id: string
          mobile?: string
          updated_at?: string
        }
        Update: {
          business_logo?: string | null
          created_at?: string
          full_name?: string
          id?: string
          mobile?: string
          updated_at?: string
        }
        Relationships: []
      }
      qr_codes: {
        Row: {
          amount: number | null
          created_at: string
          id: string
          label: string
          payload: string
          upi_id: string
          user_id: string
        }
        Insert: {
          amount?: number | null
          created_at?: string
          id?: string
          label?: string
          payload: string
          upi_id?: string
          user_id: string
        }
        Update: {
          amount?: number | null
          created_at?: string
          id?: string
          label?: string
          payload?: string
          upi_id?: string
          user_id?: string
        }
        Relationships: []
      }
      subscriptions: {
        Row: {
          amount_inr: number | null
          created_at: string
          expires_at: string | null
          id: string
          plan: Database["public"]["Enums"]["plan_tier"]
          reference: string | null
          started_at: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          amount_inr?: number | null
          created_at?: string
          expires_at?: string | null
          id?: string
          plan?: Database["public"]["Enums"]["plan_tier"]
          reference?: string | null
          started_at?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          amount_inr?: number | null
          created_at?: string
          expires_at?: string | null
          id?: string
          plan?: Database["public"]["Enums"]["plan_tier"]
          reference?: string | null
          started_at?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      activate_pro_subscription: {
        Args: { _amount?: number; _reference?: string; _user: string }
        Returns: {
          amount_inr: number | null
          created_at: string
          expires_at: string | null
          id: string
          plan: Database["public"]["Enums"]["plan_tier"]
          reference: string | null
          started_at: string | null
          updated_at: string
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "subscriptions"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      api_create_payment_link: {
        Args: {
          _amount: number
          _customer_name?: string
          _link_type?: string
          _user: string
        }
        Returns: Json
      }
      connect_merchant_account: {
        Args: { _app_password: string; _email: string; _provider: string }
        Returns: Json
      }
      create_payment_link: {
        Args: { _amount: number; _customer_name?: string; _link_type?: string }
        Returns: Json
      }
      disconnect_merchant_account: {
        Args: { _provider: string }
        Returns: Json
      }
      expire_payment_link: { Args: { _id: string }; Returns: Json }
      expire_stale_payment_links: { Args: { _user?: string }; Returns: number }
      generate_qr: {
        Args: {
          _amount?: number
          _label?: string
          _payload: string
          _upi_id?: string
        }
        Returns: Json
      }
      get_public_payment_link: { Args: { _slug: string }; Returns: Json }
      get_qr_quota: { Args: never; Returns: Json }
      issue_api_key: { Args: { _label?: string }; Returns: Json }
      list_merchant_accounts: { Args: never; Returns: Json }
      new_payment_slug: { Args: never; Returns: string }
      record_detected_payment: {
        Args: {
          _amount: number
          _email_id?: string
          _payer?: string
          _user: string
        }
        Returns: Json
      }
      register_payment_link_click: {
        Args: { _slug: string }
        Returns: undefined
      }
      revoke_api_key: { Args: { _id: string }; Returns: Json }
      save_merchant_account: {
        Args: { _payee_name?: string; _provider: string; _upi_id: string }
        Returns: Json
      }
      try_claim_mail_poll: {
        Args: { _min_gap_seconds?: number; _user: string }
        Returns: boolean
      }
    }
    Enums: {
      link_status: "active" | "paid" | "expired"
      plan_tier: "free" | "pro"
      upi_provider: "phonepe" | "paytm"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      link_status: ["active", "paid", "expired"],
      plan_tier: ["free", "pro"],
      upi_provider: ["phonepe", "paytm"],
    },
  },
} as const
