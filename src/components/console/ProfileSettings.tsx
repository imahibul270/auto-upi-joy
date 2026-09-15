import { useEffect, useRef, useState, type ChangeEvent, type FormEvent } from "react";
import type { User } from "@supabase/supabase-js";
import { Eye, EyeOff, ImageUp, LogOut, Settings, UserRound } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { supabase } from "@/integrations/supabase/client";
import { Swal } from "@/lib/swal";

const MAX_LOGO_BYTES = 512 * 1024;
const ALLOWED_LOGO_TYPES = new Set(["image/png", "image/jpeg", "image/webp"]);

function applyFavicon(source: string) {
  let favicon = document.querySelector<HTMLLinkElement>('link[rel="icon"]');
  if (!favicon) {
    favicon = document.createElement("link");
    favicon.rel = "icon";
    document.head.appendChild(favicon);
  }
  favicon.type = source.startsWith("data:image/png") ? "image/png" : "image/x-icon";
  favicon.href = source || "/favicon.ico";
}

export function ProfileSettings({
  user,
  userName,
  onSignOut,
}: {
  user: User;
  userName: string;
  onSignOut: () => Promise<void>;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [logo, setLogo] = useState("");
  const [logoMessage, setLogoMessage] = useState("");
  const [passwordMessage, setPasswordMessage] = useState("");
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [showPasswords, setShowPasswords] = useState(false);
  const [savingLogo, setSavingLogo] = useState(false);
  const [savingPassword, setSavingPassword] = useState(false);
  const initial = (userName || "M").trim().charAt(0).toUpperCase();

  useEffect(() => {
    let active = true;
    const loadLogo = async () => {
      const { data } = await supabase.from("profiles").select("business_logo").eq("id", user.id).maybeSingle();
      if (!active || !data?.business_logo) return;
      setLogo(data.business_logo);
      applyFavicon(data.business_logo);
    };
    void loadLogo();
    return () => { active = false; };
  }, [user.id]);

  function chooseLogo(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    setLogoMessage("");
    if (!ALLOWED_LOGO_TYPES.has(file.type)) {
      setLogoMessage("Use a PNG, JPG or WebP image.");
      return;
    }
    if (file.size > MAX_LOGO_BYTES) {
      setLogoMessage("Logo must be smaller than 512 KB.");
      return;
    }
    const reader = new FileReader();
    reader.onload = () => {
      if (typeof reader.result === "string") setLogo(reader.result);
    };
    reader.readAsDataURL(file);
  }

  async function saveLogo() {
    if (!logo) {
      setLogoMessage("Choose a logo first.");
      return;
    }
    setSavingLogo(true);
    setLogoMessage("");
    const { error } = await supabase.from("profiles").update({ business_logo: logo }).eq("id", user.id);
    setSavingLogo(false);
    if (error) {
      setLogoMessage(error.message);
      void Swal.fire({ icon: "error", title: "Could not save logo", text: error.message });
      return;
    }
    applyFavicon(logo);
    setLogoMessage("Business logo and favicon updated.");
    void Swal.fire({ icon: "success", title: "Logo updated", text: "Business logo and favicon updated.", draggable: true });
  }

  async function changePassword(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPasswordMessage("");
    if (newPassword.length < 8) {
      setPasswordMessage("New password must be at least 8 characters.");
      void Swal.fire({ icon: "error", title: "Password too short", text: "New password must be at least 8 characters." });
      return;
    }
    if (newPassword !== confirmPassword) {
      setPasswordMessage("New passwords do not match.");
      void Swal.fire({ icon: "error", title: "Passwords do not match", text: "Please enter the same new password in both fields." });
      return;
    }
    setSavingPassword(true);
    const { error } = await supabase.auth.updateUser({
      password: newPassword,
      current_password: currentPassword,
    });
    setSavingPassword(false);
    if (error) {
      setPasswordMessage(error.message);
      void Swal.fire({ icon: "error", title: "Could not change password", text: error.message });
      return;
    }
    setCurrentPassword("");
    setNewPassword("");
    setConfirmPassword("");
    setPasswordMessage("Password changed successfully.");
    void Swal.fire({ icon: "success", title: "Password changed", text: "Your password has been updated successfully.", draggable: true });
  }

  return (
    <>
      <div className="console-profile-wrap">
        <button
          type="button"
          className="console-menu-item console-profile-item"
          aria-expanded={menuOpen}
          aria-haspopup="menu"
          onClick={() => setMenuOpen((value) => !value)}
        >
          <UserRound />
          <span>Profile</span>
        </button>

        {menuOpen ? (
          <>
            <button type="button" className="console-menu-scrim" aria-label="Close profile menu" onClick={() => setMenuOpen(false)} />
            <div className="console-profile-menu" role="menu">
              <button
                type="button"
                role="menuitem"
                className="console-profile-menu-item"
                onClick={() => { setMenuOpen(false); setDialogOpen(true); }}
              >
                <Settings />
                <span>Profile settings</span>
              </button>
              <button
                type="button"
                role="menuitem"
                className="console-profile-menu-item is-danger"
                onClick={() => {
                  setMenuOpen(false);
                  void Swal.fire({
                    title: "Sign out?",
                    text: "You will need to sign in again to access your account.",
                    icon: "warning",
                    showCancelButton: true,
                    confirmButtonText: "Yes, sign out",
                    cancelButtonText: "Cancel",
                  }).then((result) => {
                    if (result.isConfirmed) void onSignOut();
                  });
                }}
              >
                <LogOut />
                <span>Sign out</span>
              </button>
            </div>
          </>
        ) : null}
      </div>

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="console-profile-dialog">
          <DialogHeader>
            <DialogTitle>Profile settings</DialogTitle>
            <DialogDescription>Update your business identity and account password.</DialogDescription>
          </DialogHeader>

          <section className="console-settings-section">
            <div className="console-settings-heading">
              <ImageUp />
              <div><strong>Business logo & favicon</strong><small>PNG, JPG or WebP · max 512 KB</small></div>
            </div>
            <div className="console-logo-editor">
              <span className="console-logo-preview">{logo ? <img src={logo} alt="Selected business logo" /> : initial}</span>
              <input ref={inputRef} className="sr-only" type="file" accept="image/png,image/jpeg,image/webp" onChange={chooseLogo} />
              <Button type="button" variant="outline" onClick={() => inputRef.current?.click()}>Choose logo</Button>
              <Button type="button" onClick={() => void saveLogo()} disabled={savingLogo}>{savingLogo ? "Saving…" : "Save"}</Button>
            </div>
            {logoMessage ? <p className="console-settings-message" role="status">{logoMessage}</p> : null}
          </section>

          <form className="console-settings-section" onSubmit={changePassword}>
            <div className="console-settings-heading">
              <Eye />
              <div><strong>Change password</strong><small>Your current password is required</small></div>
            </div>
            <label>Current password<Input type={showPasswords ? "text" : "password"} autoComplete="current-password" value={currentPassword} onChange={(event) => setCurrentPassword(event.target.value)} required /></label>
            <label>New password<Input type={showPasswords ? "text" : "password"} autoComplete="new-password" minLength={8} value={newPassword} onChange={(event) => setNewPassword(event.target.value)} required /></label>
            <label>Confirm new password<Input type={showPasswords ? "text" : "password"} autoComplete="new-password" minLength={8} value={confirmPassword} onChange={(event) => setConfirmPassword(event.target.value)} required /></label>
            <Button type="button" variant="ghost" className="console-password-visibility" onClick={() => setShowPasswords((value) => !value)}>
              {showPasswords ? <EyeOff /> : <Eye />}{showPasswords ? "Hide passwords" : "Show passwords"}
            </Button>
            {passwordMessage ? <p className="console-settings-message" role="status">{passwordMessage}</p> : null}
            <Button type="submit" disabled={savingPassword}>{savingPassword ? "Changing…" : "Change password"}</Button>
          </form>
        </DialogContent>
      </Dialog>
    </>
  );
}
