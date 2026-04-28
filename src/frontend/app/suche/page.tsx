"use client"
import { SearchBar } from "@/components/layout/searchbar"
import { useState } from "react";

export default function Searchpage() {
  const [search, setSearch] = useState("");   
  return (
    <div className="flex flex-col items-center justify-center min-h-screen w-full">
      <h1 className="text-2xl ">Discover Podcasts by title, subject or episode</h1>
      <div className="w-full mt-10 ml-25 mb-20 max-w-xl">
        <SearchBar value={search} onChange={setSearch} />
      </div>
    </div>
  );
}