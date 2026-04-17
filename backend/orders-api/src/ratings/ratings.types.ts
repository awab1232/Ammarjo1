import { IsIn, IsInt, IsNotEmpty, IsOptional, IsString, Max, Min } from 'class-validator';

export const RatingTargetTypes = ['technician', 'store', 'home_store', 'product', 'order'] as const;
export type RatingTargetType = (typeof RatingTargetTypes)[number];

export type RatingReview = {
  id: string;
  targetType: RatingTargetType;
  targetId: string;
  reviewerId: string;
  reviewerName: string | null;
  rating: number;
  reviewText: string | null;
  deliverySpeed: number | null;
  productQuality: number | null;
  serviceRequestId: string | null;
  orderId: string | null;
  createdAt: string;
};

export type RatingAggregate = {
  targetType: RatingTargetType;
  targetId: string;
  avgRating: number;
  totalReviews: number;
  updatedAt: string;
};

export class CreateReviewDto {
  @IsIn(RatingTargetTypes)
  targetType!: RatingTargetType;

  @IsString()
  @IsNotEmpty()
  targetId!: string;

  @IsInt()
  @Min(1)
  @Max(5)
  rating!: number;

  @IsOptional()
  @IsString()
  reviewText?: string;

  @IsOptional()
  @IsString()
  serviceRequestId?: string;

  @IsOptional()
  @IsString()
  orderId?: string;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(5)
  deliverySpeed?: number;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(5)
  productQuality?: number;
}

