export type AnalyticsSummary = {
  totalOrders: number;
  totalServiceRequests: number;
  completedServiceRequests: number;
  activeServiceRequests: number;
  totalTechnicians: number;
  avgTechnicianRating: number;
  totalRatings: number;
  totalMessages: number;
};

export type AnalyticsTimelinePoint = {
  day: string;
  orders: number;
  serviceRequestsCreated: number;
  serviceRequestsCompleted: number;
  messagesSent: number;
  ratingsCreated: number;
};

export type AnalyticsTopTechnician = {
  technicianId: string;
  avg_rating: number;
  completed_jobs: number;
  score: number;
};

export type AnalyticsSlowRequest = {
  requestId: string;
  technicianId: string | null;
  customerId: string;
  createdAt: string;
  completedAt: string;
  durationHours: number;
};

