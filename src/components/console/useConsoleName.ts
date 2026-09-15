import { useEffect, useState } from "react";
import type { User } from "@supabase/supabase-js";
import { supabase } from "@/integrations/supabase/client";

export function useConsoleName(user: User) {
  const [name, setName] = useState((user.user_metadata?.["full_name"] as string) || "Merchant");

  useEffect(() => {
    const syncProfile = async () => {
      const fullName = (user.user_metadata?.["full_name"] as string | undefined) ?? "";
      const mobile = (user.user_metadata?.["mobile"] as string | undefined) ?? "";
      const { data } = await supabase.from("profiles").select("full_name").eq("id", user.id).maybeSingle();
      if (!data) await supabase.from("profiles").insert({ id: user.id, full_name: fullName, mobile });
      else if (data.full_name) setName(data.full_name);
    };
    void syncProfile();
  }, [user]);

  return name;
}
