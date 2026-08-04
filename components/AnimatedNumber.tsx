'use client';

import { useEffect, useRef, useState } from 'react';

type AnimatedNumberProps = {
  className?: string;
  duration?: number;
  formatter?: (value: number) => string;
  value: number;
};

const defaultFormatter = (value: number) => String(Math.round(value));

function prefersReducedMotion() {
  return (
    typeof window !== 'undefined' &&
    window.matchMedia('(prefers-reduced-motion: reduce)').matches
  );
}

export function AnimatedNumber({
  className,
  duration = 520,
  formatter = defaultFormatter,
  value,
}: AnimatedNumberProps) {
  const [displayValue, setDisplayValue] = useState(value);
  const [animationKey, setAnimationKey] = useState(0);
  const previousValueRef = useRef(value);

  useEffect(() => {
    const fromValue = previousValueRef.current;

    if (fromValue === value || prefersReducedMotion()) {
      previousValueRef.current = value;
      setDisplayValue(value);
      setAnimationKey((key) => key + 1);
      return;
    }

    let frameId = 0;
    const startedAt = performance.now();
    setAnimationKey((key) => key + 1);

    function animateFrame(now: number) {
      const progress = Math.min((now - startedAt) / duration, 1);
      const easedProgress = 1 - Math.pow(1 - progress, 3);

      setDisplayValue(fromValue + (value - fromValue) * easedProgress);

      if (progress < 1) {
        frameId = requestAnimationFrame(animateFrame);
      } else {
        previousValueRef.current = value;
        setDisplayValue(value);
      }
    }

    frameId = requestAnimationFrame(animateFrame);

    return () => {
      cancelAnimationFrame(frameId);
    };
  }, [duration, value]);

  return (
    <span className={className} key={animationKey}>
      <span className="neo-number">{formatter(displayValue)}</span>
    </span>
  );
}

export default AnimatedNumber;
