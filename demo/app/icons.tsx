import type { ReactNode } from "react";

// Drawn here instead of pulled from an icon package: there are nine of them,
// and a dependency for nine paths is one more thing to keep patched.

type Props = { className?: string };

function Svg({ className, children }: Props & { children: ReactNode }) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      width="1em"
      height="1em"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {children}
    </svg>
  );
}

/** The mark beside the name: a crown, three points on a band. */
export function Mark({ className }: Props) {
  return (
    <svg className={className} viewBox="0 0 28 28" width="28" height="28" aria-hidden="true">
      <rect width="28" height="28" rx="7" fill="currentColor" />
      <path d="M6.5 19.5v-9l4.2 4.3L14 8.5l3.3 6.3 4.2-4.3v9z" fill="#94faf0" />
    </svg>
  );
}

export function ArrowRight({ className }: Props) {
  return (
    <Svg className={className}>
      <path d="M5 12h14M13 6l6 6-6 6" />
    </Svg>
  );
}

export function ArrowUpRight({ className }: Props) {
  return (
    <Svg className={className}>
      <path d="M7 17 17 7M9 7h8v8" />
    </Svg>
  );
}

export function Check({ className }: Props) {
  return (
    <Svg className={className}>
      <path d="m5 12.5 4.5 4.5L19 7.5" />
    </Svg>
  );
}

export function Layers({ className }: Props) {
  return (
    <Svg className={className}>
      <path d="m12 4 8 4-8 4-8-4zM4 12l8 4 8-4M4 16l8 4 8-4" />
    </Svg>
  );
}

export function Link({ className }: Props) {
  return (
    <Svg className={className}>
      <path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1" />
    </Svg>
  );
}

export function Alert({ className }: Props) {
  return (
    <Svg className={className}>
      <path d="M12 4 3 19h18zM12 10v4M12 17h.01" />
    </Svg>
  );
}

export function Pen({ className }: Props) {
  return (
    <Svg className={className}>
      <path d="m4 20 4-1L19 8l-3-3L5 16zM14 7l3 3" />
    </Svg>
  );
}

export function Scale({ className }: Props) {
  return (
    <Svg className={className}>
      <path d="M12 4v16M6 20h12M5 8h14M5 8l-2 6h4zM19 8l-2 6h4z" />
    </Svg>
  );
}

export function Search({ className }: Props) {
  return (
    <Svg className={className}>
      <path d="M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14zM20 20l-4-4" />
    </Svg>
  );
}
