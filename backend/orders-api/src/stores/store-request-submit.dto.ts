import { ArrayMinSize, IsArray, IsIn, IsNotEmpty, IsString, MaxLength } from 'class-validator';

/**
 * Matches the payload from [ApplyStorePage] (Flutter).
 */
export class StoreRequestSubmitDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(128)
  applicantId!: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(256)
  applicantName!: string;

  /** May be empty if the user has no email on file (matches Flutter). */
  @IsString()
  @MaxLength(320)
  applicantEmail!: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(256)
  storeName!: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(64)
  phone!: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(128)
  category!: string;

  @IsString()
  @IsNotEmpty()
  @IsIn(['city', 'all_jordan'])
  sellScope!: string;

  @IsString()
  @MaxLength(128)
  city!: string;

  @IsArray()
  @ArrayMinSize(1)
  @IsString({ each: true })
  cities!: string[];

  @IsString()
  @MaxLength(8000)
  description!: string;
}

