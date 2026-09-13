import mongoose from 'mongoose';

const SubmissionSchema = new mongoose.Schema(
  {
    userId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    status: {
      type: String,
      enum: ['draft', 'completed'],
      default: 'draft',
    },
    currentStep: { type: Number, default: 1 },
    personalData: {
      age: Number,
      gender: String,
      diabetesType: String,
      diabetesDurationYears: Number,
      bloodSugarLevel: Number,
      hba1c: Number,
      bloodPressure: String,
      smoker: String,
      additionalNotes: String,
    },
    leftEyeImage: { type: String }, // base64 data URL
    rightEyeImage: { type: String }, // base64 data URL
    // Original file name + sha256 of the file as picked, taken before the
    // browser resizes it. Used to match the upload to a pre-generated report.
    leftEyeMeta: { fileName: String, sha256: String },
    rightEyeMeta: { fileName: String, sha256: String },
    // Result of that match: grade, overlay image URLs and the report PDF URL.
    // Null when the uploaded pair isn't one of the known sets.
    analysis: { type: mongoose.Schema.Types.Mixed, default: null },
    completedAt: Date,
  },
  { timestamps: true }
);

export default mongoose.models.Submission ||
  mongoose.model('Submission', SubmissionSchema);
