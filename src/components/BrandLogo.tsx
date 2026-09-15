import logoAsset from "@/assets/autoupi-logo.jpg.asset.json";

export function BrandLogo({ className = "" }: { className?: string }) {
  return <img src={logoAsset.url} alt="Auto Upi logo" className={`brand-logo ${className}`.trim()} />;
}

export const brandLogoUrl = logoAsset.url;
