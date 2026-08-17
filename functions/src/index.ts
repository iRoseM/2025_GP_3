import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { Request, Response } from "express";

admin.initializeApp();
const db = admin.firestore();

export const getUserData = functions.https.onRequest(
  async (req: Request, res: Response): Promise<void> => {
    try {
      const userId = req.body.userId;

      if (!userId) {
        res.status(400).json({ error: "Missing userId" });
        return;
      }

      const userDoc = await db.collection("users").doc(userId).get();

      if (!userDoc.exists) {
        res.status(404).json({ error: "User not found" });
        return;
      }

      res.json(userDoc.data());
      return;

    } catch (error: any) {
      console.error(error);
      res.status(500).json({ error: error.message });
      return;
    }
  }
);