import { House, Search, AudioLines } from 'lucide-react';


export function Sidebar() {
  return (
    <div
      style={{ background: 'var(--background-card)', color: 'var(--foreground)' }}
      className="fixed top-0 left-0 h-screen z-30"
    >
      <div className="flex flex-col items-start w-50">
          <div className="ml-10 mt-5 flex items-center gap-3" > 
             <AudioLines color="var(--accent)" size={30}></AudioLines>
              <h3 style={{color:'var(--accent)'}}>Media Lens</h3>
          </div>
        <div className="ml-15 mt-15 flex items-center gap-3">
          <House size={20} />
          <a href="#" className="sidebar-link">Home</a>
        </div>

        <div className="ml-15 mt-4 flex items-center gap-3">
          <Search size={20} />
          <a href="#" className="sidebar-link">Suche</a>
        </div>

      </div>
    </div>
  )
}