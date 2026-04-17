export type TechnicianScoreBreakdown = {
  ratingScore: number;
  completionRateScore: number;
  responsivenessScore: number;
  fallbackScore: number;
};

export type TechnicianScoreResult = {
  technicianId: string;
  score: number;
  breakdown: TechnicianScoreBreakdown;
};

